library(shiny)
library(ggplot2)
library(phyloseq)
library(data.table)
source("../common/mbiome/mbiome-reader.R")
source("../common/ggplot_ext/eupath_default.R")
source("../common/tooltip/tooltip.R")
source("../common/config.R")

shinyServer(function(input, output, session) {
  
  mstudy_obj <- NULL
  
  # this should be a static variable for all R sessions
  NO_METADATA_SELECTED <- "Choose the sample details"
  WIDTH <- global_width
  
  # Declaring some global variables
  # df_abundance, df_sample and df_sample.formatted are declared global to avoid 
  # multiple file reading in the reactive section
  df_abundance <- NULL
  df_sample <- NULL
  df_sample.formatted <- NULL
  
  richness_object <- NULL
  
  all_measures <- c("Chao1", "ACE", "Shannon", "Simpson", "Fisher")
  
  phyloseq_obj <- NULL
  
  # global objects to read in more than one function
  columns <- NULL
  hash_sample_names<- NULL
  hash_count_samples <- NULL
  
  ggplot_object<-NULL
  ggplot_data <- NULL
  ggplot_build_object <- NULL
  
  ggplot_object_mt<-NULL
  ggplot_data_mt <- NULL
  ggplot_build_object_mt <- NULL
  
  abundance_otu <- NULL
  abundance_taxa <- NULL
  
  MAX_SAMPLES_NO_RESIZE <- 40
  MIN_HEIGHT_AFTER_RESIZE <- 9.5
  
  maximum_samples_without_resizing <- 40
  minimum_height_after_resizing <- 9
  
  load_microbiome_data <- reactive({
    if(is.null(mstudy_obj)){
      # abundance_file <- "MicrobiomeSampleByMetadata_TaxaRelativeAbundance.txt"
      # sample_file <- "MicrobiomeSampleByMetadata_Characteristics.txt"
      # 
      # mstudy_obj <<- import.eupath(
      #   taxa_abundance_path = abundance_file,
      #   sample_path = sample_file,
      #   aggregate_by = "Species",
      #   use_relative_abundance = F
      # )
      mstudy_obj <<- import.biom(biom_file, metadata_details, use_relative_abundance=F)
      
      updateSelectizeInput(session, "category",
                           choices = c(
                                       mstudy_obj$get_filtered_categories()),
                           options = list(placeholder = NO_METADATA_SELECTED),
                           server = TRUE)
      
      updateSelectizeInput(session, "categoryFacet1",
                           choices = c(
                             mstudy_obj$get_filtered_categories()),
                           options = list(placeholder = "First choose the x-axis"),
                           server = TRUE)
      
      updateSelectizeInput(session, "categoryFacet2",
                           choices = c(
                             mstudy_obj$get_filtered_categories()),
                           options = list(placeholder = "First choose the x-axis"),
                           server = TRUE)
      
      phyloseq_obj <- mbiome2phyloseq(mstudy_obj, "Species")
      
      richness_object <<- estimate_richness(phyloseq_obj, measures = all_measures)
      richness_object$SampleName <<- gsub("\\.", "\\-", rownames(richness_object))
      richness_object$SampleName <<- gsub("^X", "", rownames(richness_object))
    }
    
    mstudy_obj
  })
  
  
  allSamples <- function(){}
  
  output$allSamplesChart <- renderUI({
    shinyjs::hide("allSamplesArea")
    shinyjs::show("chartLoading")
    
    mstudy <- load_microbiome_data()
    measure<-input$measure
    plotRadio <- input$plotTypeRadio
    quantity_samples <- mstudy$get_sample_count()
    result_to_show<-NULL
    
    if(identical(measure,"") | is.na(measure) | !(measure %in% all_measures) ){
      output$allSamplesDt <- renderDataTable(NULL)
      result_to_show<-h5(class="alert alert-danger", "Please choose at least one alpha diversity measure.")
    }else{
      
      if(identical(measure, "Chao1")){
        se <- "se.chao1"
        rich <- richness_object[,c("SampleName", measure,se)]
      }else if(identical(measure, "ACE")){
        se <- "se.ACE"
        rich <- richness_object[,c("SampleName", measure,se)]
      }else{
        rich <- richness_object[,c("SampleName", measure)]
        se = NULL
      }
      
      rich$SampleName<-factor(rich$SampleName, levels=rich$SampleName)
      data_melted<-melt(rich, id.vars = c("SampleName"),  measure.vars=measure)
      
      if(!is.null(se)){
        se_melted <-melt(rich, id.vars = c("SampleName"),  measure.vars=se)
        se_melted[,"variable"]<-measure
        colnames(se_melted)<-c("SampleName", "variable", "se")
        data_melted<-merge(data_melted,se_melted,by=c("SampleName", "variable"), all.x=T)
      }else{
        data_melted$se<-0 # see if this is necessary
      }
      
      if(identical(plotRadio, "dotplot")){
        chart <- ggplot(data_melted, aes_string(x="value", y="SampleName"))+
          geom_point(shape = 21, alpha=1, colour = "grey", fill = "black", size = 3, stroke = 1.5)+
          theme_eupath_default(
            panel.border = element_rect(colour="black", size=1, fill=NA),
            axis.text.y = element_text(size=rel(0.9))
          )+
          labs(x="Alpha Diversity",  y="Samples")
        
        if(!is.null(se)){
          chart<-chart+geom_errorbarh(aes(xmax=value + se, xmin=value - se), height = .1)
        }
          
      } # end if is dotplot
      else{
        chart<-ggplot(data_melted, aes(variable, value))+geom_boxplot()+
          theme_eupath_default(
            panel.border = element_rect(colour="black", size=1, fill=NA),
            axis.text.x = element_blank(),
            axis.ticks.x =  element_blank()
          )+
          labs(x="All Samples", y="Alpha Diversity")
      }
      
      
      
      
      ggplot_object <<- chart
      ggplot_build_object <<- ggplot_build(chart)
      
      output$allSamplesWrapper<-renderPlot({
        ggplot_object
      })
      
      if(is.null(se)){
        colnames(rich)<-c("Sample Name", measure)
      }else{
        colnames(rich)<-c("Sample Name", measure, "Std. Error")
      }
      
      output$allSamplesDt = renderDataTable(
        rich,
        options = list(
          order = list(list(0, 'asc'))
        )
      )
      
      if(quantity_samples <= MAX_SAMPLES_NO_RESIZE | identical(plotRadio, "boxplot")){
        result_to_show<-plotOutput("allSamplesWrapper",
                                   hover = hoverOpts("plot_hover", delay = 60, delayType = "throttle"),
                                   width = paste0(WIDTH,"px"),
                                   height = "500px"
        )
      }else{
        h <- quantity_samples*MIN_HEIGHT_AFTER_RESIZE
        if(h>2500){
          h<-2500
        }
        result_to_show<-plotOutput("allSamplesWrapper",
                                   hover = hoverOpts("plot_hover", delay = 60, delayType = "throttle"),
                                   width = paste0(WIDTH,"px"),
                                   # width = "100%",
                                   height = h
        )
      }
      
      
      
    }
    
    shinyjs::hide("chartLoading", anim = TRUE, animType = "slide")
    shinyjs::show("allSamplesArea")
    return(result_to_show)
  })
  
  byMetadata <- function(){}
  output$byMetadataChart <- renderUI({
    mstudy <- load_microbiome_data()
    result_to_show<-NULL
    # reactive values
    measure<-input$measure
    plotRadio <- input$plotTypeRadio
    # category <- category_button()
    category <- input$category
    verticalCategory <- input$categoryFacet1
    horizontalCategory <- input$categoryFacet2
    
    if(identical(measure,"") | is.na(measure) | !(measure %in% all_measures) ){
      output$byMetadataDt <- renderDataTable(NULL)
      output$result_tests <- renderUI(NULL)
      result_to_show<-h5(class="alert alert-warning", "Please choose at least one alpha diversity measure.")
    }else if(is.null(category) | identical(category, "")){
      output$byMetadataDt <- renderDataTable(NULL)
      output$result_tests <- renderUI(NULL)
      result_to_show<-h5(class="alert alert-warning", "Please choose the sample detail for the X-Axis.")
    }else if(identical(category, verticalCategory) | identical(category, horizontalCategory)){
      output$byMetadataDt <- renderDataTable(NULL)
      output$result_tests <- renderUI(NULL)
      result_to_show<-h5(class="alert alert-warning", "Please choose different sample details.")
    }
    else{
      shinyjs::hide("metadataContent")
      shinyjs::show("metadataLoading")
      
      quantity_samples <- mstudy$get_sample_count()
      output$byMetadataDt <- renderDataTable(NULL)
      
      condVertical <- identical(verticalCategory, "")
      condHorizontal <- identical(horizontalCategory, "")
      
      if(!condVertical & !condHorizontal){
        all_columns<-c(category, verticalCategory, horizontalCategory)
      }else if(!condVertical & condHorizontal){
        all_columns<-c(category, verticalCategory)
      }else if(condVertical & !condHorizontal){
        all_columns<-c(category, horizontalCategory)
      }else{
        all_columns<-c(category)
      }
      # print(all_columns)
      # print(mstudy$get_metadata_as_column("host diet"))
      dt_metadata<-mstudy$get_metadata_as_column(all_columns)
      
      if(identical(measure,"Chao1")){
        rich <- richness_object[,c("SampleName", measure,"se.chao1")]
      }else if(identical(measure,"ACE")){
        rich <- richness_object[,c("SampleName", measure,"se.ACE")]
      }else{
        rich <- richness_object[,c("SampleName", measure)]
      }
      
      richness_merged <- merge(dt_metadata, rich, by = "SampleName")
      # richness_merged<-na.omit(richness_merged)
      # data_melted<-melt(richness_merged, id.vars = c("SampleName", category),  measure.vars=measure)
      # print("richness_merged")
      
      if(identical(class(richness_merged[[category]]),"numeric")){
        if(!condVertical){
          chart<-ggplot(richness_merged,
                        aes_string(x=sprintf("`%s`", category), y=measure, color=sprintf("`%s`", verticalCategory)))+
            theme_eupath_default(
              panel.border = element_rect(colour="black", size=1, fill=NA),
              axis.text.x = element_text(size=rel(0.9),face="bold"),
              axis.text.y = element_text(size=rel(0.8),face="bold")
            )+
            labs(x=paste(category), y="Alpha Diversity") 
        }else{
          chart<-ggplot(richness_merged,
                        aes_string(x=sprintf("`%s`", category), y=measure))+
            theme_eupath_default(
              panel.border = element_rect(colour="black", size=1, fill=NA),
              axis.text.x = element_text(size=rel(0.9),face="bold"),
              axis.text.y = element_text(size=rel(0.8),face="bold")
            )+
            labs(x=paste(category), y="Alpha Diversity") 
        }
        # scale_x_discrete(labels = function(x) lapply(strwrap(x, width = 10, simplify = FALSE), paste, collapse="\n"))+
        
        if(identical(plotRadio, "dotplot")){
            chart<-chart+
              geom_point(shape = 20, alpha=0.7, size = 2)+
              geom_smooth(method = "loess", span = 0.7)
        } # end if is dotplot
        else{
          chart<-chart+
            geom_boxplot()
        }
        
        if(!condHorizontal){
          joined_categories <- sprintf(" `%s` ~ .", horizontalCategory)
          chart <- chart+facet_grid(as.formula(joined_categories)) 
          # output$result_tests <- renderUI(NULL)
        }
        
        if(!condHorizontal | !condVertical){
          output$result_tests <- renderUI(NULL)
        }else{
          output$result_tests <- renderUI(runStatisticalTests(category, measure, chart$data))
        }
        
        output$byMetadataChartWrapper<-renderPlot({
          chart
        })
        
      }else{
        chart<-ggplot(richness_merged, aes_string(sprintf("`%s`",category), measure))+
          theme_eupath_default(
            panel.border = element_rect(colour="black", size=1, fill=NA),
            axis.text.x = element_text(size=rel(0.9),face="bold"),
            axis.text.y = element_text(size=rel(0.8),face="bold")
          )+
          labs(x=paste(category), y="Alpha Diversity")
        # scale_x_discrete(labels = function(x) lapply(strwrap(x, width = 10, simplify = FALSE), paste, collapse="\n"))+
        
        if(identical(plotRadio, "dotplot")){
          chart<-chart+
            geom_point(shape = 21, alpha=1, colour = "grey", fill = "black", size = 3, stroke = 1.5)
          if(!identical(class(richness_merged[[category]]),"numeric")){
            chart<-chart+
              geom_smooth(method = "loess", span = 0.7)
          }
          # geom_errorbar(aes(ymax=value + se, ymin=value - se), height = .1) # error
        } # end if is dotplot
        else{
          chart<-chart+
            geom_boxplot()
        }
        
        if(!condHorizontal & condVertical){
          joined_categories <- sprintf(" `%s` ~ .", horizontalCategory)
        }else if(!condHorizontal & !condVertical){
          joined_categories <- sprintf("`%s` ~`%s`", horizontalCategory, verticalCategory)
        }else if(condHorizontal & !condVertical){
          joined_categories <- sprintf("~ `%s`", verticalCategory)
        }
        
        if(!condHorizontal | !condVertical){
          chart <- chart+facet_grid(as.formula(joined_categories)) 
          output$result_tests <- renderUI(NULL)
        }else{
          output$result_tests <- renderUI(runStatisticalTests(category, measure, chart$data))
        }
        
        output$byMetadataChartWrapper<-renderPlot({
          chart
        })
      }
      
      formatTable(richness_merged, measure, category, verticalCategory, horizontalCategory)
      
      
      ggplot_object_mt<<-chart
      ggplot_build_object_mt<<-ggplot_build(chart)
      
      if(quantity_samples <= maximum_samples_without_resizing | identical(plotRadio, "boxplot") |
         identical("numeric",class(richness_merged[[category]]))){
        result_to_show<-plotOutput("byMetadataChartWrapper",
                                  hover = hoverOpts("hoverByMetadata", delay = 60, delayType = "throttle"),
                                  # width = "100%", height = "500px"
                                  width = paste0(WIDTH,"px"), height = "500px"
        )
      }else{
        h <- quantity_samples*MIN_HEIGHT_AFTER_RESIZE
        if(h>2500){
          h<-2500
        }
        result_to_show<-plotOutput("byMetadataChartWrapper",
                                   hover = hoverOpts("hoverByMetadata", delay = 60, delayType = "throttle"),
                                   width = paste0(WIDTH,"px"),
                                   height = h
        )
      }
      
      shinyjs::hide("metadataLoading", anim = TRUE, animType = "fade")
      shinyjs::show("metadataContent")
    }
    result_to_show
  })
  
  formatTable <- function(richness_merged, measure, category, verticalCategory, horizontalCategory){
    condVertical <- identical(verticalCategory, "")
    condHorizontal <- identical(horizontalCategory, "")
    if(!condVertical & !condHorizontal){
      colnames(richness_merged)<-c("Sample Name", category, verticalCategory, horizontalCategory, measure)
      output$byMetadataDt = renderDataTable(
        richness_merged,
        options = list(
          order = list(list(0, 'desc'))
        )
      )
    }else if(!condVertical & condHorizontal){
      colnames(richness_merged)<-c("Sample Name", category, verticalCategory, measure)
      output$byMetadataDt = renderDataTable(
        richness_merged,
        options = list(
          order = list(list(0, 'desc'))
        )
      )
    }else if(condVertical & !condHorizontal){
      colnames(richness_merged)<-c("Sample Name", category, horizontalCategory, measure)
      output$byMetadataDt = renderDataTable(
        richness_merged,
        options = list(
          order = list(list(0, 'desc'))
        )
      )
    }else{
      colnames(richness_merged)<-c("Sample Name", category, measure)
      output$byMetadataDt = renderDataTable(
        richness_merged,
        options = list(
          order = list(list(0, 'desc'))
        )
      )
    }
  }
  
  
  # category_button <- eventReactive(input$doneButton, {
  #   input$category
  # })
  
  runStatisticalTests <- function(category, measures, gg_data){
    html_formatted<-"<ul class=\"shell-body\"> %s</ul>"
    
    if(length(category)==1){
      levels_df <- levels(factor(gg_data[[category]]))
      if(length(levels_df)==2){
        html_formatted<-sprintf(html_formatted, "<li>Wilcoxon rank sum test:%s</li>")
      }else{
        html_formatted<-sprintf(html_formatted, "<li>Kruskal-Wallis rank sum test:%s</li>")
      }
      
      text <- ""
      # for(i in 1:length(measures)){
        # df<-subset(gg_data, variable==measures[i])
        df_to_run <- gg_data[,c(category,measures),with=F]
        
        if(length(levels_df)==2){
          suppressWarnings(
            result<-wilcox.test(df_to_run[[2]] ~ df_to_run[[1]])
          )
          text<-paste0(text, sprintf("<br>[%s]: W = %f, p-value = %.8f", measures, result$statistic, result$p.value))
        }else{
          suppressWarnings(
            result<-kruskal.test(df_to_run[[1]] ~ df_to_run[[2]])
          )
          text<-paste0(text, sprintf("<br>[%s]: chi-squared = %f, df = %f, p-value = %.8f", measures, result$statistic, result$parameter, result$p.value))
        }
      # }
      html_formatted<-HTML(sprintf(html_formatted, text))
    }else{
      html_formatted <- NULL
    }
    html_formatted
  }
  
  
  hovers <- function(){}
  
  output$uiHoverAllSamples <- renderUI({
    hover <- input$plot_hover
    
    isolate(typeRadio<-input$plotTypeRadio)
    isolate(measure<-input$measure)
    
    if (is.null(hover$x) || round(hover$x) <0 || round(hover$y)<0 || is.null(hover$y))
      return(NULL)
    
    tooltip<-NULL
    if(identical(typeRadio, "dotplot")){
      measures_with_se <- c("Chao1","ACE")
      if(measure %in% measures_with_se){
        columns_to_show<-c("SampleName", "variable", "value", "se")
        renamed_columns <- c("Sample", "Measure", "Alpha Div.", "Std. Err.")
        tooltip<-generic_point(hover, ggplot_build_object, ggplot_object$data, WIDTH,
                                                        -68, 28, 28, columns_to_show, renamed_columns)
      }else{
        columns_to_show<-c("SampleName", "variable", "value")
        renamed_columns <- c("Sample", "Measure", "Alpha Div.")

        tooltip<-generic_point(hover, ggplot_build_object, ggplot_object$data, WIDTH,
                                 -55, 28, 28, columns_to_show, renamed_columns)
      }
    }else{
      tooltip<-generic_boxplot(hover, ggplot_build_object, WIDTH, 0, 20,20)
    }
    
    tooltip
  })
  
  output$uiHoverByMetadata <- renderUI({
    hover <- input$hoverByMetadata
    
    return(NULL)
    
    isolate(typeRadio<-input$plotTypeRadio)
    isolate(measure<-input$measure)
    
    if (is.null(hover$x) || round(hover$x) <0 || round(hover$y)<0 || is.null(hover$y))
      return(NULL)
    
    # hover$panelvar1<-ifelse(is.null(hover$panelvar1), "NA", hover$panelvar1)
    
    isolate(category<-input$category)
    
    if(identical(typeRadio, "dotplot")){
      all_columns<-colnames(ggplot_object_mt$data)
      
      measures_with_se <- c("Chao1","ACE")
      names(measures_with_se)<-c("se.chao1","se.ACE")
      if(hover$panelvar1  %in% measures_with_se){
        have_measures_se<-measures_with_se %in% measure
        columns_to_show<-all_columns
        renamed_columns <- c("Sample", "Measure", category, "Alpha Div.", "Std. Err.")
        
        if(length(category)==1){
          tooltip<-generic_point(hover, ggplot_build_object_mt, ggplot_object_mt$data, WIDTH,
                               -80, 28, 28, columns_to_show, renamed_columns)
        }else if(length(category)==2){
          tooltip<-generic_point(hover, ggplot_build_object_mt, ggplot_object_mt$data, WIDTH,
                                 -94, 28, 28, columns_to_show, renamed_columns)
        }
        else{
          tooltip<-generic_point(hover, ggplot_build_object_mt, ggplot_object_mt$data, WIDTH,
                                 -108, 28, 28, columns_to_show, renamed_columns)
        }
      }else{
        columns_to_show<-all_columns[1:(length(all_columns)-1)]
        renamed_columns <- c("Sample", category, "Measure", "Alpha Div.")
        
        if(length(category)==1){
          tooltip<-generic_point(hover, ggplot_build_object_mt, ggplot_object_mt$data, WIDTH,
                                 -66, 28, 28, columns_to_show, renamed_columns)
        }else if(length(category)==2){
          tooltip<-generic_point(hover, ggplot_build_object_mt, ggplot_object_mt$data, WIDTH,
                                 -80, 28, 28, columns_to_show, renamed_columns)
        }else{
          tooltip<-generic_point(hover, ggplot_build_object_mt, ggplot_object_mt$data, WIDTH,
                                 -94, 28, 28, columns_to_show, renamed_columns)
        }
      }
    }else{
      # tooltip<-generic_boxplot(hover, ggplot_build_object_mt, WIDTH, 0, 20, 20)
      tooltip<-NULL
      # return(tooltip)
    }
    return(tooltip)
    
  })
  
  # downloads
  downloadButtons <- function(){}
  
  output$btnDownloadPNG <- downloadHandler(
    filename = "plot.png",
    content = function(file) {
      isolate(selected_tab<-input$tabs)
      png(file, width=1200,height=800,units="px")
      if(identical(selected_tab, "firstTab")){
        print(ggplot_object)
      }else{
        print(ggplot_object_mt)
      }
      dev.off()
    }
  )
  
  output$btnDownloadEPS <- downloadHandler(
    filename = "plot.eps",
    content = function(file) {
      isolate(selected_tab<-input$tabs)
      setEPS()
      postscript(file, width=16,height=10.67, family = "Helvetica")
      if(identical(selected_tab, "firstTab")){
        print(ggplot_object)
      }else{
        print(ggplot_object_mt)
      }
      dev.off()
    }
  )
  
  output$btnDownloadSVG <- downloadHandler(
    filename = "plot.svg",
    content = function(file) {
      isolate(selected_tab<-input$tabs)
      svg(file, width=16,height=10.67)
      if(identical(selected_tab, "firstTab")){
        print(ggplot_object)
      }else{
        print(ggplot_object_mt)
      }
      dev.off()
    }
  )
  
  output$btnDownloadCSV <- downloadHandler(
    filename = "data.csv",
    content = function(file) {
      isolate(selected_tab<-input$tabs)
      if(identical(selected_tab, "firstTab")){
        write.csv(ggplot_object$data, file)
      }else{
        write.csv(ggplot_object_mt$data, file)
      }
    }
  )
  
  
  
  shinyjs::hide(id = "loading-content", anim = TRUE, animType = "fade")
  shinyjs::show("app-content")
}) # end shinyServer
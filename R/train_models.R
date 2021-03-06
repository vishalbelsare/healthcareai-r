#' Fit models
#'
#' @return list of models to be passed with details to as.model_list
#' @noRd
train_models <- function(d, outcome, models, metric, train_control,
                         hyperparameters, tuned, allow_parallel) {

  mes <- if (tuned) "Training with cross validation: " else "Training at fixed values: "

  train_list <-
    lapply(models, function(model) {

      tune_grid <- as.data.frame(unname(hyperparameters[model]))

      model <- translate_model_names(model)
      message(mes, caret::getModelInfo(model)[[1]]$label)

      # Make initial list of arguments to pass to train
      train_args <- list(x = select_not(d, outcome),
                         y = dplyr::pull(d, !!outcome),
                         method = model,
                         metric = metric,
                         trControl = train_control,
                         tuneGrid = tune_grid)

      # Add arguments specific to models
      if (model == "ranger") {
        train_args$importance <- "impurity"
        if (nrow(d) >= 1e5 || ncol(d) >= 100)
          message("You may, or may not, see messages about progress in growing trees. ",
                  "The estimates are very rough, and you should expect the progress ",
                  "ticker to cycle ", train_control$number + 1, " times.")
      } else if (model == "xgbTree") {
        train_args$allowParallel <- allow_parallel
      }

      # caret loads packages at runtime, we don't want to see those startup messages
      suppressPackageStartupMessages({
        # Often get a single missing performance metric warning that doesn't
        # hurt anything, so silence it
        withCallingHandlers(
          expr = do.call(caret::train, train_args),
          warning = function(w) {
            if (grepl("missing values in resampled", w))
              invokeRestart("muffleWarning")
          })
      })

    })
  message("\n*** Models successfully trained. The model object contains the training data minus ignored ID columns. ***\n",
          "*** If there was PHI in training data, normal PHI protocols apply to the model object. ***")
  structure(train_list, positive_class = levels(dplyr::pull(d, !!outcome))[2]) %>%
    attach_session_info()
}

attach_session_info <- function(x) {
  si <- sessionInfo()
  structure(x,
            versions = list(
              r_version = paste0(si$R.version$major, ".", si$R.version$minor),
              hcai_version = installed.packages()["healthcareai", "Version"],
              other_packages =
                purrr::map_chr(si$loadedOnly, ~ .x$Version) %>%
                tibble::tibble(package = names(.), version = .))
  )
}

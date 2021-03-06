#' Defines a TML Estimator for Variable Importance for Continuous Interventions
#'
#' Current limitations: pretty much tailored to \code{Param_TSM}
#' See TODO notes for places generalization can be added
#'
#' @importFrom R6 R6Class
#' @importFrom tmle3 tmle3_Spec define_lf tmle3_Update Targeted_Likelihood
#'  Param_TSM
#'
#' @export
#
tmle3_Spec_vimshift_msm <- R6::R6Class(
  classname = "tmle3_Spec_vimshift_msm",
  portable = TRUE,
  class = TRUE,
  inherit = tmle3_Spec,
  public = list(
    initialize = function(shift_fxn = shift_additive_bounded,
                              shift_fxn_inv = shift_additive_bounded_inv,
                              shift_grid = seq(-1, 1, by = 0.5),
                              max_shifted_ratio = 2,
                              ...) {
      options <- list(
        shift_fxn = shift_fxn,
        shift_fxn_inv = shift_fxn_inv,
        shift_grid = shift_grid,
        max_shifted_ratio = max_shifted_ratio
      )
      shift_args_extra <- list(...)
      do.call(super$initialize, options)
    },
    make_params = function(tmle_task, likelihood) {
      # TODO: export and use sl3:::get_levels
      A_vals <- tmle_task$get_tmle_node("A")
      if (is.factor(A_vals)) {
        msg <- paste(
          "This parameter is defined as a series of shifts of a continuous",
          "treatment. The treatment detected is NOT continuous."
        )
        stop(msg)
      }

      # unwrap internalized arguments
      shift_fxn <- self$options$shift_fxn
      shift_fxn_inv <- self$options$shift_fxn_inv
      shift_grid <- self$options$shift_grid
      max_shifted_ratio <- self$options$max_shifted_ratio

      # define shift intervention over grid (additive only for now)
      interventions <-
        lapply(shift_grid, function(x) {
          tmle3::define_lf(LF_shift,
            name = "A",
            original_lf = likelihood$factor_list[["A"]],
            likelihood_base = likelihood, # initial likelihood
            shift_fxn, shift_fxn_inv, # shift fxns
            shift_delta = x,
            max_shifted_ratio = max_shifted_ratio
          )
        })

      # create list of counterfactual means (parameters)
      tsm_params_list <-
        lapply(interventions, function(x) {
          tmle3::Param_TSM$new(likelihood, x)
        })

      # MSM function factory
      design_matrix <- cbind(rep(1, length(shift_grid)), shift_grid)
      colnames(design_matrix) <- c("intercept", "slope")
      delta_param_MSM_linear <- msm_linear_factory(design_matrix)

      # instantiate linear working MSM
      msm_linear_param <- Param_MSM_linear$new(
        observed_likelihood = likelihood,
        delta_param = delta_param_MSM_linear,
        parent_parameters = tsm_params_list,
      )

      # output should be a list
      return(msm_linear_param)
    },
    make_updater = function() {
      updater <- tmle3_Update$new(cvtmle = FALSE)
    }
  ),
  active = list(),
  private = list()
)

#################################################################################

#' Outcome Under a Grid of Shifted Interventions via Targeted Working MSM
#'
#' O = (W, A, Y)
#' W = Covariates
#' A = Treatment (binary or categorical)
#' Y = Outcome (binary or bounded continuous)
#'
#' @param shift_fxn A \code{function} defining the type of shift to be applied
#'  to the treatment. For an example, see \code{shift_additive}.
#' @param shift_fxn_inv A \code{function} defining the inverse of the type of
#'  shift to be applied to the treatment. For an example, see
#'  \code{shift_additive_inv}.
#' @param shift_grid A \code{numeric} vector, specification of a selection of
#'  shifts (on the level of the treatment) to be applied to the intervention.
#'  This is a value passed to the \code{function}s above for computing various
#'  values of the outcome under modulated values of the treatment.
#' @param max_shifted_ratio A \code{numeric} value indicating the maximum
#'  tolerance for the ratio of the counterfactual and observed intervention
#'  densities. In particular, the shifted value of the intervention is assigned
#'  to a given observational unit when the ratio of counterfactual intervention
#'  density to the observed intervention density is below this value.
#' @param ... Additional arguments, passed to shift functions.
#'
#' @importFrom sl3 make_learner Lrnr_mean
#'
#' @export
#
tmle_vimshift_msm <- function(shift_fxn = shift_additive_bounded,
                              shift_fxn_inv = shift_additive_bounded_inv,
                              shift_grid = seq(-1, 1, by = 0.5),
                              max_shifted_ratio = 2,
                              ...) {
  # TODO: unclear why this has to be in a factory function
  tmle3_Spec_vimshift_msm$new(
    shift_fxn, shift_fxn_inv,
    shift_grid, max_shifted_ratio,
    ...
  )
}

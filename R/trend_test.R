#' Test for a trend in the effect of shift interventions
#'
#' @param tmle_fit_estimates A \code{list} corresponding to the
#'  \code{$estimates} slot of an object of class \code{tmle3_Fit}, containing
#'  estimates of a grid of posited shift interventions.
#' @param delta_grid A \code{numeric} vector giving the individual values of the
#'  shift parameter used in computing each of the TML estimates.
#' @param level The nominal coverage probability of the confidence interval.
#' @param weights A \code{numeric} vector indicating the weights (if any) to be
#'  applied to each of the estimated mean counterfactual outcomes under posited
#'  values of the shift parameter delta. The default is to weight each estimate
#'  by the inverse of its variance, in order to improve stability; however, this
#'  may be changed depending on the exact choice of shift function.
#'
#' @importFrom stats cov qnorm pnorm
#' @importFrom methods is
#' @importFrom assertthat assert_that
#'
#' @export
#
trend_msm <- function(tmle_fit_estimates, delta_grid, level = 0.95,
                      weights = NULL) {

  # make sure more than one parameter has been estimated for trend
  assert_that(length(tmle_fit_estimates) > 1)

  # matrix of EIF(O_i) values and estimates across each parameter estimated
  eif_mat <- sapply(tmle_fit_estimates, `[[`, "IC")
  psi_vec <- sapply(tmle_fit_estimates, `[[`, "psi")

  # set weights to be the inverse of the variance of each TML estimate
  if (is.null(weights)) {
    weights <- as.numeric(1 / diag(stats::cov(eif_mat)))
  }

  # multiplier for CI construction
  ci_mult <- (c(1, -1) * stats::qnorm((1 - level) / 2))

  # compute the MSM parameters
  intercept <- rep(1, length(delta_grid))
  x_mat <- cbind(intercept, delta_grid)
  omega <- diag(weights)
  s_mat <- solve(t(x_mat) %*% omega %*% x_mat) %*% t(x_mat) %*% omega
  msm_param <- as.vector(s_mat %*% psi_vec)

  # compute inference for MSM based on individual EIF(O_i) for each parameter
  msm_eif <- t(tcrossprod(s_mat, eif_mat))
  msm_var <- diag(stats::cov(msm_eif))
  msm_se <- sqrt(msm_var / nrow(msm_eif))

  # build confidence intervals and hypothesis tests for EIF(msm)
  ci_msm_param <- msm_se %*% t(ci_mult) + msm_param
  pval_msm_param <- 2 * stats::pnorm(-abs(msm_param / msm_se))

  # marix for output
  out <- cbind(
    ci_msm_param[, 1], msm_param, ci_msm_param[, 2], msm_se,
    pval_msm_param
  )
  colnames(out) <- c("ci_low", "param_est", "ci_high", "param_se", "p_value")
  rownames(out) <- names(msm_se)
  return(out)
}

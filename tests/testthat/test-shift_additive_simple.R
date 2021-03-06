context("Simple additive shift intervention results match classic")

library(uuid)
library(assertthat)
library(data.table)
library(future)
library(sl3)
library(tmle3)
library(ranger)
set.seed(429153)

################################################################################
# setup data and learners for tests
################################################################################

## simulate simple data for tmle-shift sketch
n_obs <- 1000 # number of observations
n_w <- 1 # number of baseline covariates
tx_mult <- 2 # multiplier for the effect of W = 1 on the treatment
delta_value <- 0.5 # value of the shift parameter

## baseline covariates -- simple, binary
W <- as.numeric(replicate(n_w, rbinom(n_obs, 1, 0.5)))

## create treatment based on baseline W
A <- as.numeric(rnorm(n_obs, mean = tx_mult * W, sd = 1))

## create outcome as a linear function of A, W + white noise
Y <- A + W + rnorm(n_obs, mean = 0, sd = 1)

## organize data and nodes for tmle3
data <- data.table(W, A, Y)
node_list <- list(W = "W", A = "A", Y = "Y")


# learners used for conditional expectation regression (e.g., outcome)
lrn1 <- Lrnr_mean$new()
lrn2 <- Lrnr_glm$new()
lrn3 <- Lrnr_ranger$new()
sl_lrn <- Lrnr_sl$new(
  learners = list(lrn1, lrn2, lrn3),
  metalearner = Lrnr_nnls$new()
)

# learners used for conditional density regression (e.g., propensity score)
lrn1_dens <- Lrnr_condensier$new(
  nbins = 25, bin_estimator = lrn1,
  bin_method = "dhist"
)
lrn2_dens <- Lrnr_condensier$new(
  nbins = 20, bin_estimator = lrn2,
  bin_method = "dhist"
)
lrn3_dens <- Lrnr_condensier$new(
  nbins = 15, bin_estimator = lrn3,
  bin_method = "dhist"
)
lrn4_dens <- Lrnr_condensier$new(
  nbins = 10, bin_estimator = lrn2,
  bin_method = "dhist"
)
sl_lrn_dens <- Lrnr_sl$new(
  learners = list(lrn1_dens, lrn2_dens, lrn3_dens, lrn4_dens),
  metalearner = Lrnr_solnp_density$new()
)

# specify outcome and treatment regressions and create learner list
Q_learner <- sl_lrn
g_learner <- sl_lrn_dens
learner_list <- list(Y = Q_learner, A = g_learner)


################################################################################
# setup and compute TMLE of shift intervention parameter with tmle3_shift
################################################################################

# initialize a tmle specification
tmle_spec <- tmle_shift(
  shift_val = delta_value,
  shift_fxn = shift_additive,
  shift_fxn_inv = shift_additive_inv
)

## define data (from tmle3_Spec base class)
tmle_task <- tmle_spec$make_tmle_task(data, node_list)

## define likelihood (from tmle3_Spec base class)
likelihood_init <- tmle_spec$make_initial_likelihood(tmle_task, learner_list)

## define update method (submodel and loss function)
updater <- tmle_spec$make_updater()
likelihood_targeted <- Targeted_Likelihood$new(likelihood_init, updater)

## define param
tmle_params <- tmle_spec$make_params(tmle_task, likelihood_targeted)
updater$tmle_params <- tmle_params

## fit tmle update
tmle_fit <- fit_tmle3(tmle_task, likelihood_targeted, tmle_params, updater)

## extract results from tmle3_Fit object
tmle_fit
tmle3_psi <- tmle_fit$summary$tmle_est
tmle3_se <- tmle_fit$summary$se


################################################################################
# compute numerical result using classical implementation (txshift R package)
################################################################################
library(txshift)
set.seed(429153)

## TODO: validate that we're getting the same errors on g fitting
tmle_sl_shift_classic <- tmle_txshift(
  W = W, A = A, Y = Y, delta = delta_value,
  fluc_method = "standard",
  g_fit_args = list(
    fit_type = "sl",
    sl_lrnrs = g_learner
  ),
  Q_fit_args = list(
    fit_type = "sl",
    sl_lrnrs = Q_learner
  )
)

## extract results from fit object produced by classical package
summary(tmle_sl_shift_classic)
classic_psi <- tmle_sl_shift_classic$psi
classic_se <- sqrt(tmle_sl_shift_classic$var)


################################################################################
# test numerical equivalence of tmle3 and classical implementations
################################################################################

## only approximately equal (although it's O(1/n))
test_that("Parameter point estimate matches result from classic package", {
  expect_equal(tmle3_psi, classic_psi, tol = 6 * (1 / n_obs),
               scale = tmle3_psi)
})

## only approximately equal (although it's O(1/n))
test_that("Standard error matches result from classic package", {
  expect_equal(tmle3_se, classic_se, tol = 1 / n_obs, scale = classic_se)
})

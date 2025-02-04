library(checkpoint)
checkpoint("2018-07-01")

library(devtools)
library(OpenML)
library(batchtools)
#OMLbots_path = "/home/probst/Paper/Exploration_of_Hyperparameters/OMLbots"
#OMLbots_path = "C:/Promotion/Hyperparameters/OMLbots"
#load_all(OMLbots_path)
load_all()
lrn.par.set = getMultipleLearners()

# Get file from the figshare repository
load(url("https://ndownloader.figshare.com/files/10811309"))

# From wide format to long
#a = read.csv(url("https://ndownloader.figshare.com/files/10462300"))

#a = read.csv(url("https://ndownloader.figshare.com/files/10811312"))
#library(xtable)
#head(a)
#table(a$data_id)

################################ Restrict data to 500000 results for each algorithm
data.ids = calculateDataIds(tbl.results, tbl.hypPars, min.experiments = 200)
# Only results for OpenML100 datasets
#tasks = listOMLTasks(number.of.classes = 2L, tag = "OpenML100", estimation.procedure = "10-fold Crossvalidation", number.of.missing.values = 0)
#data.ids = data.ids[data.ids %in% tasks$data.id]

# Change the sign for the brier score to get the correct results
tbl.results$brier = -tbl.results$brier

library(stringi)
learner.names = paste0("mlr.", names(lrn.par.set))
learner.names = stri_sub(learner.names, 1, -5)
measures = c("auc", "accuracy", "brier")
measure = c("auc")

################################ Compare different surrogate models (complete)

# only models which do not have to be tuned!
surrogate.mlr.lrns = list(
  makeLearner("regr.lm"),
  makeLearner("regr.rpart"),
  makeLearner("regr.kknn"),
  makeLearner("regr.ranger"),
#  makeLearner("regr.ranger", par.vals = list(num.trees = 2000, respect.unordered.factors = "order")),
  makeLearner("regr.cubist")
  #makeLearner("regr.xgboost", par.vals = list(nrounds = 300, eta = 0.03, max_depth = 2, nthread = 1)),
  #makeLearner("regr.svm"),
  #makeLearner("regr.bartMachine"),
  #makeLearner("regr.glmnet"), 
  #makeLearner("regr.brnn"), # too many errors
  #makeLearner("regr.km")
)

k = 2
i = 6
bmr = list()

load(paste0("bmr_", measures[k], ".RData"))

for(k in 1:3) {
  configureMlr(show.info = TRUE, on.learner.error = "warn", on.learner.warning = "warn", on.error.dump = TRUE)
  library("parallelMap")
  parallelStartSocket(5)
  for (i in 1:6) {
    print(i)
    set.seed(521 + i)
    # task.id 146085, 14966 does not work for svm
      bmr[[i]] = compareSurrogateModels(measure.name = measures[k], learner.name = learner.names[i], 
        data.ids = data.ids, tbl.results, tbl.metaFeatures, tbl.hypPars, lrn.par.set, surrogate.mlr.lrns)
    gc()
    save(bmr, file = paste0("bmr_", measures[k], ".RData"))
  }
parallelStop()
names(bmr) = learner.names

for(i in seq_along(bmr)) {
  print(i)
  rmat = convertBMRToRankMatrix(bmr[[i]])
  print(rmat)
  print(plotBMRSummary(bmr[[i]], measure = kendalltau))
  print(plotBMRBoxplots(bmr[[i]], style = "violin"))
  print(plotBMRRanksAsBarChart(bmr[[i]], pos = "stack"))
}
bmr_surrogate = bmr

# replace NA results of lm/kknn, rsq
for(i in seq_along(data.ids)) {
  for(j in seq_along(learner.names)) {
    for(l in seq_along(surrogate.mlr.lrns)) {
      rsq = bmr_surrogate[[j]]$results[[i]][[l]]$measures.test$rsq
      bmr_surrogate[[j]]$results[[i]][[l]]$aggr[2] = mean(rsq[rsq>0], na.rm = T)
      bmr_surrogate$mlr.classif.kknn$results[[i]][[l]]$aggr[3] = 
        mean(bmr_surrogate$mlr.classif.kknn$results[[i]][[l]]$measures.test$kendalltau, na.rm = T)
      bmr_surrogate$mlr.classif.kknn$results[[i]][[l]]$aggr[4] = 
        mean(bmr_surrogate$mlr.classif.kknn$results[[i]][[l]]$measures.test$spearmanrho, na.rm = T)
    }
  }
}

# Save results
save(bmr_surrogate, file = paste0("results_", measures[k], ".RData"))


# Best model in general: ranger, cubist

################################# Calculate tunability measures
surrogate.mlr.lrn = makeLearner("regr.ranger", par.vals = list(num.threads = 4))
#surrogate.mlr.lrn = makeLearner("regr.ranger", par.vals = list(num.trees = 2000, respect.unordered.factors = "order", num.threads = 4))
#surrogate.mlr.lrn = makeLearner("regr.cubist")

results = list()

for(i in seq_along(learner.names)) {
  print(i)
  set.seed(199 + i)
  # Surrogate model calculation
  surrogates = makeSurrogateModels(measure.name = measures[k], learner.name = learner.names[i], 
    data.ids = data.ids, tbl.results, tbl.metaFeatures, tbl.hypPars, lrn.par.set, surrogate.mlr.lrn)
  save(surrogates, file = paste0("surrogates_", measures[k], "_", i, ".RData"))
}

for(i in seq_along(learner.names)) {
  print(i)
  set.seed(199 + i)
  load(paste0("surrogates_", measures[k], "_", i, ".RData"))
  # Default calculation
  default = calculateDefault(surrogates)
  # Tunability overall
  optimum = calculateDatasetOptimum(surrogates, default, hyperpar = "all", n.points = 100000)
  # Tunability hyperparameter specific
  optimumHyperpar = calculateDatasetOptimum(surrogates, default, hyperpar = "one", n.points = 100000)
  # Tunability for two hyperparameters
  optimumTwoHyperpar = calculateDatasetOptimum(surrogates, default, hyperpar = "two", n.points = 10000)
  # Tuning space
  tuningSpace = calculateTuningSpace(optimum, quant = 0.05)
    
  results[[i]] = list(default = default,  optimum = optimum, optimumHyperpar = optimumHyperpar, 
    optimumTwoHyperpar = optimumTwoHyperpar, tuningSpace = tuningSpace)
  gc()
  save(bmr_surrogate, results, file = paste0("results_", measures[k], ".RData"))
}
names(results) = learner.names

# Calculations
default = results$mlr.classif.xgboost$default
optimum = results$mlr.classif.xgboost$optimum
optimumHyperpar = results$mlr.classif.xgboost$optimumHyperpar
overallTunability = calculateTunability(default, optimum)
mean(overallTunability)
tunability = calculateTunability(default, optimumHyperpar)
data.frame(t(colMeans(tunability)))
# scaled
data.frame(t(colMeans(tunability/overallTunability, na.rm = T)))

default$default[is.numeric(default$default)] = default$default[,is.numeric(default$default)]

def = default$default

for(i in 1:length(def)) {
  if(is.numeric(def[[i]]))
    def[[i]] = round(def[[i]], 3)
}

# Interaction
# Bare values
tab = colMeans(results$mlr.classif.xgboost$optimumTwoHyperpar$optimum, dims = 1, na.rm = TRUE) - 
  mean(results$mlr.classif.xgboost$default$result)
diag(tab) = colMeans(tunability)
colnames(tab) = rownames(tab) = names(tunability)
tab
# Interaction
colMeans(results$mlr.classif.xgboost$optimumTwoHyperpar$optimum, dims = 1, na.rm = TRUE) - 
  mean(results$mlr.classif.xgboost$default$result) - 
  outer(colMeans(tunability), colMeans(tunability), '+')
# Performance gain
colMeans(results$mlr.classif.xgboost$optimumTwoHyperpar$optimum, dims = 1, na.rm = TRUE) - 
  mean(results$mlr.classif.xgboost$default$result) - 
  outer(colMeans(tunability), colMeans(tunability), pmax)

# Package defaults
package.defaults = list(
  glmnet = data.frame(alpha = 1, lambda = 0), # no regularization
  rpart = data.frame(cp = 0.01, maxdepth = 30, minbucket = 7, minsplit = 20),
  kknn = data.frame(k = 7),
  svm = data.frame(kernel = "radial", cost = 1, gamma = 1, degree = 3), 
  ranger = data.frame(num.trees = 500, replace = TRUE, sample.fraction = 1, mtry  = 0.1, respect.unordered.factors = FALSE, min.node.size = 0),
  xgboost = data.frame(nrounds = 500, eta = 0.3, subsample = 1, booster = "gbtree", max_depth = 6, min_child_weight = 1,
    colsample_bytree = 1, colsample_bylevel = 1, lambda = 1, alpha = 1)
)

# Parameters dependent on data characteristics: svm: gamma, ranger: mtry. 
# Not Specified: glmnet: alpha, xgboost: nrounds
resultsPackageDefaults = list()

for(i in seq_along(learner.names)) {
  print(i)
  set.seed(199 + i)
  load(paste0("surrogates_", measures[k], "_", i, ".RData"))
  
  def = package.defaults[[i]]
  default = calculatePackageDefaultPerformance(surrogates, def, tbl.metaFeatures, tbl.results)
  optimumHyperpar = calculateDatasetOptimumPackageDefault(surrogates, default, hyperpar = "one", n.points = 100000, tbl.metaFeatures, tbl.results)
  optimumTwoHyperpar = calculateDatasetOptimumPackageDefault(surrogates, default, hyperpar = "two", n.points = 10000, tbl.metaFeatures, tbl.results)
  resultsPackageDefaults[[i]] = list(default = default,  optimumHyperpar = optimumHyperpar, optimumTwoHyperpar = optimumTwoHyperpar)
  save(bmr_surrogate, results, resultsPackageDefaults, file = paste0("results_", measures[k], ".RData"))
}
names(resultsPackageDefaults) = learner.names

resultsPackageDefaults$mlr.classif.svm$default$default$gamma = "1/p"
resultsPackageDefaults$mlr.classif.ranger$default$default$mtry = "sqrt(p)"
resultsPackageDefaults$mlr.classif.ranger$default$default$min.node.size = "1"

save(bmr_surrogate, results, resultsPackageDefaults, file = paste0("results_", measures[k], ".RData"))

# Calculations
default = resultsPackageDefaults$mlr.classif.ranger$default
optimum = results$mlr.classif.ranger$optimum
optimumHyperpar = resultsPackageDefaults$mlr.classif.ranger$optimumHyperpar
overallTunability = calculateTunability(default, optimum)
mean(overallTunability)

tunability = calculateTunability(default, optimumHyperpar)

data.frame(t(colMeans(tunability)))
# scaled
data.frame(t(colMeans(tunability/overallTunability, na.rm = T)))

# KI for tunability
y = overallTunability
hist(y)
qqnorm(y)
qqline(y)

t_value = qt(0.975, length(y) - 1)
mean(y) + c(-t_value, t_value) * sd(y) / sqrt(length(y))

# Tunability of the "algorithm"; overfitting problem!
the_order = order(results[[5]]$default$result)
plot(results$mlr.classif.glmnet$default$result[the_order], type = "l", ylab = "AUC")
avg_results = numeric(6)
best_results = best_results_default = numeric(length(results$mlr.classif.glmnet$default$result))

for(i in seq_along(learner.names)) {
  lines(results[[i]]$default$result[the_order], col = i)
  avg_results[i] = mean(results[[i]]$default$result)
  for(j in 1:length(results[[i]]$default$result)) {
    best_results_default[j] = ifelse(results[[i]]$default$result[j] > best_results[j], results[[i]]$default$result[j], best_results[j])
    best_results[j] = ifelse(results[[i]]$optimum$optimum[j] > best_results[j], results[[i]]$optimum$optimum[j], best_results[j])
  }
}
legend("topleft", legend = substr(learner.names, 13, 100), col = 1:6, lty = 1)

round(best_results - (results[[5]]$default$result), 3)
mean(best_results_default - (results[[5]]$default$result))
mean(best_results - (results[[5]]$default$result))

mean((results[[5]]$default$result) - (results[[6]]$default$result))
# maybe overfitting! 

# Make Crossvalidation to test if there is overfitting
results_cv = list()
for(i in 1:6) {
  print(i)
  set.seed(3000 + i)
  load(paste0("surrogates_", measures[k], "_", i, ".RData"))
  
  # CV
  n_surr = length(surrogates$surrogates)
  shuffle = sample(n_surr)
  folds = cut(shuffle, breaks = 5, labels = FALSE)
  
  default = list()
  optimumHyperpar = list()
  optimumTwoHyperpar = list()
  
  for(j in 1:5) {
    print(paste(j,i))
    testInd = which(folds == j, arr.ind = TRUE)
    trainInd = which(folds != j, arr.ind = TRUE)
    
    # Default calculation
    default1 = calculateDefault(surrogates = list(surrogates = surrogates$surrogates[trainInd], param.set = surrogates$param.set))
    # Calculate performance of these defaults on test datasets
    default[[j]] = calculatePerformance(list(surrogates = surrogates$surrogates[testInd], param.set = surrogates$param.set), default1$default)
    # Tunability hyperparameter specific
    optimumHyperpar[[j]] = calculateDatasetOptimum(surrogates = list(surrogates = surrogates$surrogates[testInd], param.set = surrogates$param.set), default[[j]], hyperpar = "one", n.points = 100000)
    # Tunability for two hyperparameters
    optimumTwoHyperpar[[j]] = calculateDatasetOptimum(list(surrogates = surrogates$surrogates[testInd], param.set = surrogates$param.set), default[[j]], hyperpar = "two", n.points = 10000)
    
    results_cv[[i]] = list(default = default, optimumHyperpar = optimumHyperpar, optimumTwoHyperpar = optimumTwoHyperpar)
    gc()
  }
  save(bmr_surrogate, results, resultsPackageDefaults, results_cv, file = paste0("results_", measures[k], ".RData"))
}
names(results_cv) = learner.names
save(bmr_surrogate, results, resultsPackageDefaults, results_cv, lrn.par.set, file = paste0("results_", measures[k], ".RData"))
}

# overall tunability, cross-validated
for(i in seq_along(learner.names)){
  print(learner.names[i])
  print(mean(calculateTunability(results[[i]]$default, results[[i]]$optimum)))
  print(mean(results[[i]]$optimum$optimum - unlist(sapply(results_cv[[i]]$default, "[[", 2))))
}
for(i in seq_along(learner.names)){
  print(learner.names[i])
  print(rbind(colMeans(calculateTunability(results[[i]]$default, results[[i]]$optimumHyperpar)),
  colMeans(do.call(rbind, unlist(results_cv[[i]]$optimumHyperpar, recursive=FALSE)) - unlist(sapply(results_cv[[i]]$default, "[[", 2)))))
}

# Save results for shiny

results_auc = NULL
names = load("results_auc.RData")
for(i in seq_along(names))
  results_auc[[i]] = get(names[i])
names(results_auc) = names
results_accuracy = NULL
names = load("results_accuracy.RData")
for(i in seq_along(names))
  results_accuracy[[i]] = get(names[i])
names(results_accuracy) = names
results_brier = NULL
names = load("results_brier.RData")
for(i in seq_along(names))
  results_brier[[i]] = get(names[i])
names(results_brier) = names

results_all = list(auc = results_auc, accuracy = results_accuracy, brier = results_brier)
save(results_all, file = "./shiny/results_all.RData")

# Annex

lrn.regr = makeLearner("regr.ksvm")
fit.regr = train(lrn.regr, bh.task)
fa = generateFunctionalANOVAData(fit.regr, bh.task, "lstat", depth = 1, fun = median)


# Defaults normalized (check if results differ substantially)

results_normalized = list()
k = 1
for(i in seq_along(learner.names)) {
  print(i)
  load(paste0("surrogates_", measures[k], "_", i, ".RData"))
  # Defaults with normalization
  default = calculateDefault(surrogates, normalization = TRUE)
  # Tunability hyperparameter specific
  optimumHyperpar = calculateDatasetOptimum(surrogates, default, hyperpar = "one", n.points = 100000)
  # Tunability for two hyperparameters
  #optimumTwoHyperpar = calculateDatasetOptimum(surrogates, default, hyperpar = "two", n.points = 10000)
  # Tuning space
  results_normalized[[i]] = list(default = default,  optimumHyperpar = optimumHyperpar)
  gc()
  save(results_normalized, file = paste0("./results_normalized_", measures[k], ".RData"))
}


for(i in 1:6){
  print(learner.names[i])
  print(rbind(results_normalized[[i]]$default$default, results[[i]]$default$default))
  print("Tunability")
  print(mean(calculateTunability(results_normalized[[i]]$default, results[[i]]$optimum)))
  print(mean(calculateTunability(results[[i]]$default, results[[i]]$optimum)))
  print("Tunability parameter")
  print(rbind(colMeans(calculateTunability(results_normalized[[i]]$default, results[[i]]$optimumHyperpar)),
    colMeans(calculateTunability(results[[i]]$default, results_normalized[[i]]$optimumHyperpar))))
  print("--------------------------------------------------------------------------------------------------------")
}

# xtable version
library(xtable)
for(i in 1:6){
  defs = rbind(results_normalized[[i]]$default$default, results[[i]]$default$default)
  rownames(defs) = c("norm", "mean")
  colnames(defs) = substr(colnames(defs), 1, 5)
  print(xtable(defs, caption = paste(learner.names[i], "defaults"), digits = 3))
  tuna = rbind(
    c(mean(calculateTunability(results_normalized[[i]]$default, results[[i]]$optimum)), 
      colMeans(calculateTunability(results_normalized[[i]]$default, results[[i]]$optimumHyperpar))),
    c(mean(calculateTunability(results[[i]]$default, results[[i]]$optimum)), 
      colMeans(calculateTunability(results[[i]]$default, results[[i]]$optimumHyperpar)))
  )
  colnames(tuna)[1] = "all"
  colnames(tuna) = substr(colnames(tuna), 1, 5)
  rownames(tuna) = c("norm", "mean")
  print(xtable(tuna, caption = paste(learner.names[i], "tunability"), digits = 3))
}

# rpart sieht sehr komisch aus!

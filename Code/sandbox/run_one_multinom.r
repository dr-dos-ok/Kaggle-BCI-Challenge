#
# Template for hold-out-subjects cross-validation. You need to change 6 things here.
#

# 1) SPECIFIFY PACKAGES TO USE DURING LEARNING HERE
# this is needed because we need to pass them to each parallel cluster separately
packages=c('pROC', 'caret')

library('foreach')
library('doParallel')
library('parallel')
source('../functions.r')
for (pkg in packages) {
    library(pkg, character.only=T)
}

# On the server the global package directory is not writable
# you might want to specify your local one here
.libPaths('/home/kuzovkin/R/x86_64-unknown-linux-gnu-library/3.0')

# 2) SPECIFY THE DATA FOLDER (WITH THE dataset.rds FILE PRODUCED BY ONE OF Code/preprocessing/extract_*.r SCRIPTS)
datafolder <- 'eye8ch1300ms80pca'
dataset <- readRDS(paste('../../Data/', datafolder, '/dataset.rds', sep=''))

# 3) SPECIFY THE METHOD YOU USE (NEEDED JUST FOR RECORD)
mlmethod <- 'multinom'

# 4) ENLIST PARAMETERS HERE
parameters <- list()
parameters[['maxit']] <- c(100)
parameters[['decay']] <- c(20)

# 5) THIS FUNCITON SHOULD RETURN classifier OBJECT
# @param p: current set of parameters
# @param trainingset: set to train model on
buildmodel <- function(p, trainingset) {
    tunegrid <- data.frame(decay=p$decay)
    trcontrol <- trainControl(method='none')
    classifier <- train(class ~., data=trainingset, 'multinom', trControl=trcontrol, tuneGrid=tunegrid,
                        maxit=p$maxit, MaxNWts=10000)
}

# 6) THIS FUNCITON SHOULD RETURN VECTOR OF PREDICTED PROBABILITIES
# @param classifier: classifier to use to predict
# @param validset: set to validate results on
makeprediction <- function(classifier, validset) {
    predicted <- predict(classifier, newdata=validset, type='prob')$positive
    return(predicted)
}



# ------- In happy circumstances you should not look below this line ------- #

# measure time
timestart <- Sys.time()

# configure parallel foreach execution
ncores <- floor(detectCores() * 0.5)  # take 1/3 of available processors
cl <- makeCluster(ncores)
registerDoParallel(cl)

# initalize parameter search grid
results <- buildgrid(parameters)

# read in current parameter set
p <- results[1, ]

# loop over cross-validation (training, validation) pairs
scores <- foreach(cv = 1:length(dataset$cvpairs), .combine='rbind', .packages=packages) %dopar% {
    
    # take cv pair
    cvpair <- dataset$cvpairs[[cv]]
    
    # train a model
    classifier <- buildmodel(p, cvpair$train)
    
    # make a prediciton on a validation and training sets
    predicted.prob.out <- makeprediction(classifier, cvpair$valid)
    predicted.prob.in <-  makeprediction(classifier, cvpair$train)
    
    # identify current subject rows in the training set
    subjectlist <- read.table('../../Data/train_subject_list.csv', sep=',', header=F)
    subjects <- sort(as.numeric(unique(subjectlist)$V1))
    cvsubject <- subjects[cv]
    train.idx <- which(subjectlist != cvsubject)
    valid.idx <- which(subjectlist == cvsubject)
    
    # load meta predictions on the training set
    predicted.meta <- read.table('../../Data/train_meta_predictions.csv', sep=',', header=T)
    predicted.meta <- predicted.meta$Prediction
    
    # combine brain and meta predictions
    predicted.meta.out <- predicted.meta[valid.idx]
    predicted.meta.in  <- predicted.meta[train.idx]
    predicted.prob.out <- (predicted.prob.out + predicted.meta.out) / 2
    predicted.prob.in  <- (predicted.prob.in + predicted.meta.in) / 2
    
    # add genstats predictions
    predicted.stats <- read.table('../../Data/train_genstats8ch1300ms_gbm.csv', sep=',', header=T)
    predicted.stats <- predicted.stats$Prediction
    predicted.stats.out <- predicted.stats[valid.idx]
    predicted.stats.in  <- predicted.stats[train.idx]
    predicted.prob.out <- (predicted.prob.out + predicted.stats.out) / 2
    predicted.prob.in  <- (predicted.prob.in + predicted.stats.in) / 2
    
    # add record to results table
    if (is.na(predicted.prob.out[1])) {
        cat('WARNING: Was not able to predict probabilities. Deal with it.')
        score.out <- -1
        score.in <- -1
    } else {
        score.out <- as.numeric(roc(cvpair$valid$class, predicted.prob.out)$auc)
        score.in  <- as.numeric(roc(cvpair$train$class, predicted.prob.in)$auc)
    }
    
    data.frame('in-score'=score.in, 'out-score'=score.out)
}

# stop parallel processing cluster
stopCluster(cl)

# Tell how long the whole process took
print(Sys.time() - timestart)

# show results
print(scores)
print(colMeans(scores))

# train final classifier
classifier <- buildmodel(p, dataset$train)

# produce result
predicted <- makeprediction(classifier, dataset$test)
result <- data.frame(read.table('../../Results/SampleSubmission.csv', sep = ',', header = T))
result$Prediction = predicted
write.table(result, paste('../../Results/subX_', datafolder, '_meta_genstats_', mlmethod, '.csv', sep=''), sep=',', quote=F, row.names=F, col.names=T)












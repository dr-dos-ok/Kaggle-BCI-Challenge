#
#  Extract cross-validation pairs (training, validation) such that division is base on subjects
#

# load libraries
.libPaths('/home/kuzovkin/R/x86_64-unknown-linux-gnu-library/3.0')
library('data.table')

# load data
train.path <- '../../Data/raw/train'
train.files <- dir(train.path, pattern='Data.*\\.csv', full.names=T)
train.tables <- lapply(train.files, fread)
train.nrows <- sapply(train.tables, nrow)
train.subjs <- as.numeric(substr(train.files, 28, 29))
train.sess <- as.numeric(substr(train.files, 35, 36))
for (i in 1:length(train.tables)) {
  train.tables[[i]] = cbind.data.frame(train.tables[[i]], 'Session'=rep(train.sess[[i]]),
                                       'Subject'=rep(train.subjs[i], train.nrows[i]))
}
train.orig <- do.call(rbind, train.tables)

test.path <- '../../Data/raw/test'
test.files <- dir(test.path, pattern='Data.*\\.csv', full.names=T)
test.tables <- lapply(test.files, fread)
test.nrows <- sapply(test.tables, nrow)
test.subjs <- as.numeric(substr(test.files, 27, 28))
test.sess <- as.numeric(substr(test.files, 34, 35))
for (i in 1:length(test.tables)) {
  test.tables[[i]] = cbind.data.frame(test.tables[[i]], 'Session'=rep(test.sess[[i]]),
                                      'Subject'=rep(test.subjs[i], test.nrows[i]))
}
test.orig <- do.call(rbind, test.tables)

# extract 2 seconds after the feedback
extract <- function(dataset) {
  counter <- 0
  fb.idx <- which(dataset$FeedBackEvent == 1)
  result <- data.frame()
  
  # counters
  prev_sess <- -1
  
  # loop over feedback events
  for (fbi in fb.idx) {
    counter <- counter + 1
    
    # update counters
    if (prev_sess != dataset$Session[fbi]) {
      sfbcounter <- 0
      prev_sess <- dataset$Session[fbi]
    }
    sfbcounter <- sfbcounter + 1
    
    result <- rbind.data.frame(result, c(dataset[fbi:(fbi + 259), Cz], sfbcounter, dataset[fbi, Time] * 200,
                                         dataset$Session[fbi], dataset$Subject[fbi]))
    cat(counter, '/', length(fb.idx), '\r')
  }
  cat('\n')
  colnames(result)[ncol(result)-3] <- 'FeedbackNo'
  colnames(result)[ncol(result)-2] <- 'FeedbackTime'
  colnames(result)[ncol(result)-1] <- 'Session'
  colnames(result)[ncol(result)] <- 'Subject'
  return(result)
}
train.orig <- extract(train.orig)
test.orig <- extract(test.orig)

# PCA
topca <- function(train, test) {
  mf.train.idx <- grep("FeedbackNo|FeedbackTime|Session|Subject", colnames(train))
  mf.train <- train[, mf.train.idx]
  bf.train <- train[, -mf.train.idx]
  pca.train <- prcomp(bf.train, center=T, scale.=T)
  cumvar <- cumsum(pca.train$sdev / sum(pca.train$sdev))
  keep <- which(cumvar <= 0.99)
  pca.train <- pca.train$x[, keep]
  pca.train <- cbind.data.frame(pca.train, mf.train)
  
  mf.test.idx <- grep("FeedbackNo|FeedbackTime|Session|Subject", colnames(test))
  mf.test <- test[, mf.test.idx]
  bf.test <- test[, -mf.test.idx]
  pca.test <- prcomp(bf.test, center=T, scale.=T)
  pca.test <- pca.test$x[, keep]
  pca.test <- cbind.data.frame(pca.test, mf.test)
  
  return(list('train'=pca.train, 'test'=pca.test))
}

pcaset <- topca(train.orig, test.orig)

train.orig <- pcaset$train
test.orig <- pcaset$test

# add labels
labels <- fread('../../Data/TrainLabels.csv')
train.orig <- cbind.data.frame(train.orig, labels$Prediction[1:nrow(train.orig)])

# split into 4 pairs (training, validation)
#
# @param vidx: vector of test subject's which will go into the validation set c(1,2,3,4)
extractpair <- function(vidx) {
  
  # extract validation and training data
  valid.idx <- subjects[ vidx]
  train.idx <- subjects[-vidx]
  valid <- subset(train.orig, Subject %in% valid.idx)
  train <- subset(train.orig, Subject %in% train.idx)
  
  # modify factors and names
  valid[, ncol(valid)] <- as.factor(valid[, ncol(valid)])
  train[, ncol(train)] <- as.factor(train[, ncol(train)])
  colnames(valid) <- c(paste("A_", 1:(length(colnames(valid)) - 5), sep=""),
                       'FeedbackNo', 'FeedbackTime', 'Session', 'Subject', 'class')
  colnames(train) <- c(paste("A_", 1:(length(colnames(train)) - 5), sep=""),
                       'FeedbackNo', 'FeedbackTime', 'Session', 'Subject', 'class')
  valid$class <- as.factor(ifelse(valid$class == 1, "positive", "negative"))
  train$class <- as.factor(ifelse(train$class == 1, "positive", "negative"))
  
  return(list('train'=train, 'valid'=valid))
}

# extract cv pairs
subjects <- sort(as.numeric(unique(train.orig$Subject)))
cvpairs <- list()
cvpairs[[1]] <- extractpair(c(1:4))
cvpairs[[2]] <- extractpair(c(5:8))
cvpairs[[3]] <- extractpair(c(9:12))
cvpairs[[4]] <- extractpair(c(13:16))

# prepare train set column names and factors
train.orig[, ncol(train.orig)] <- as.factor(train.orig[, ncol(train.orig)])
colnames(train.orig) <- c(paste("A_", 1:(length(colnames(train.orig)) - 5), sep=""),
                          'FeedbackNo', 'FeedbackTime', 'Session', 'Subject', 'class')
train.orig$class <- as.factor(ifelse(train.orig$class == 1, "positive", "negative"))

# prepare test set column names
colnames(test.orig) <- c(paste("A_", 1:(length(colnames(test.orig)) - 4), sep=""),
                         'FeedbackNo', 'FeedbackTime', 'Session', 'Subject')

# store the resulting dataset
dataset = list('cvpairs'=cvpairs, 'train'=train.orig, 'test'=test.orig)
folder = 'cz2sec_pca_meta'
system(paste('mkdir ../../Data/', folder, sep=''))
saveRDS(dataset, paste('../../Data/', folder, '/dataset.rds', sep=''))


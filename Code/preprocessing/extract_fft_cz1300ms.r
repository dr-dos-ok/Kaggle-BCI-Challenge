#
#  Extract cross-validation pairs (training, validation) such that division is base on subjects
# 
#  FFT( Cz[ feedback : feedback + 1300ms ] )
#

# load libraries
.libPaths('/home/kuzovkin/R/x86_64-unknown-linux-gnu-library/3.0')
library('data.table')
library('zoo')

# load data
train.path <- '../../Data/raw/train'
train.files <- dir(train.path, pattern='Data.*\\.csv', full.names=T)
train.tables <- lapply(train.files, fread)
train.nrows <- sapply(train.tables, nrow)
train.subjs <- as.numeric(substr(train.files, 28, 29))
for (i in 1:length(train.tables)) {
  train.tables[[i]] = cbind.data.frame(train.tables[[i]], 'Subject'=rep(train.subjs[i], train.nrows[i]))
}
train.orig <- do.call(rbind, train.tables)

test.path <- '../../Data/raw/test'
test.files <- dir(test.path, pattern='Data.*\\.csv', full.names=T)
test.tables <- lapply(test.files, fread)
test.nrows <- sapply(test.tables, nrow)
test.subjs <- as.numeric(substr(test.files, 27, 28))
for (i in 1:length(test.tables)) {
  test.tables[[i]] = cbind.data.frame(test.tables[[i]], 'Subject'=rep(test.subjs[i], test.nrows[i]))
}
test.orig <- do.call(rbind, test.tables)

#
# Perform FFT on piece of signal
# @param x: signal in time domain
# @return: signal in frequency domain
#
fourier_transform_on_window <- function(x) {
  
  # parameters
  srate <- 200
  maxfreq <- srate / 2  # nyquist
  window <- 1:length(x)
  binsize <- round(length(x) / srate) * 1
  
  # detrend
  trend <- lm(x ~ window)
  detrended_data <- trend$residuals
  
  # fft
  fourier_components_norm <- abs(fft(detrended_data)) / (length(detrended_data) / 2)
  fourier_components_half <- fourier_components_norm[1:min((length(fourier_components_norm) / 2), maxfreq)]
  
  # put into 1 Hz buckets
  fourier_compoenets_buckets <- split(fourier_components_half, ceiling(seq_along(fourier_components_half) / binsize))
  fourier_compoenets_buckets <- sapply(fourier_compoenets_buckets, mean)
  fourier_compoenets_buckets <- fourier_compoenets_buckets[1:length(fourier_compoenets_buckets)-1]
  
  return(fourier_components_half)
}

# extract new features
extract <- function(dataset) {
  counter <- 0
  fb.idx <- which(dataset$FeedBackEvent == 1)
  result <- data.frame()
  for (fbi in fb.idx) {
    counter <- counter + 1
    result <- rbind.data.frame(result, c(fourier_transform_on_window(dataset[fbi:(fbi + 260), Cz]),
                                         dataset$Subject[fbi]))
    cat(counter, '/', length(fb.idx), '\r')
  }
  cat('\n')
  colnames(result)[ncol(result)] <- 'Subject'
  return(result)
}
train.orig <- extract(train.orig)
test.orig <- extract(test.orig)

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
  
  # remove subject information
  valid$Subject <- NULL
  train$Subject <- NULL
  
  # modify factors and names
  valid[, ncol(valid)] <- as.factor(valid[, ncol(valid)])
  train[, ncol(train)] <- as.factor(train[, ncol(train)])
  colnames(valid) <- c(paste("A_", 1:(length(colnames(valid)) - 1), sep=""), 'class')
  colnames(train) <- c(paste("A_", 1:(length(colnames(train)) - 1), sep=""), 'class')
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

# drop subject data
train.orig$Subject <- NULL
test.orig$Subject <- NULL

# prepare train set column names and factors
train.orig[, ncol(train.orig)] <- as.factor(train.orig[, ncol(train.orig)])
colnames(train.orig) <- c(paste("A_", 1:(length(colnames(train.orig)) - 1), sep=""), 'class')
train.orig$class <- as.factor(ifelse(train.orig$class == 1, "positive", "negative"))

# prepare test set column names
colnames(test.orig) <- c(paste("A_", 1:(length(colnames(test.orig))), sep=""))

# store the resulting dataset
dataset = list('cvpairs'=cvpairs, 'test'=test.orig, 'train'=train.orig)
folder = 'fft_cz1300ms'
system(paste('mkdir ../../Data/', folder, sep=''))
saveRDS(dataset, paste('../../Data/', folder, '/dataset.rds', sep=''))








#
# Split dataset into pieces and apply fft on each piece
# @param dt: dataset to split
# @param size: number of time points in one piece
# @param step: shift of the floating window (in time moments)
#
pieces <- function(dt, size, step) {
  rollapply(dt, size, by=step, function(x) fourier_transform_on_window(x))
}

#
# Perform FFT on each channel (column) of the dataset using sliding window
# @param dt: the dataset to work with
# @param window_size: Fourier window size (in time moments)
# @param step: sliding window step (in time moments)
#
fft_per_ch_per_slice <- function(dt, window_size, step){
  colnames(dt) <- as.character(colnames(dt))
  fft_per_ch_per_slice <- c()
  electrodes = c("Cz")
  for (electrode in electrodes) {
    print(electrode)
    fft_per_slice <- pieces(dt[, electrode, with=F], window_size, step)
    fft_per_ch_per_slice <- cbind(fft_per_ch_per_slice, fft_per_slice)
  }
  return(fft_per_ch_per_slice)
}

# fft_per_ch_per_slice <- fft_per_ch_per_slice(Data_S02_Sess01, window_size=200, step=200)


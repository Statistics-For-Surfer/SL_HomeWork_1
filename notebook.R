rm(list = ls())

# Set reproducibility -----------------------------------------------------
seed <- 981126
set.seed(seed) 

# Libraries and Data ---------------------------------------------------------------
library(glmnet)
library(NMOF)
library(parallel)
library(snow)

test_set_vero <- read.csv("test.csv")
train_set <- read.csv("train.csv")

#quant <- range(quantile(train_set$y, c(0.25, 0.75)))
#Lower <- quant[1] - 1.5*(diff(quant))
#Upper <- quant[2] + 1.5*(diff(quant))

#train_set <- train_set[(train_set$y > Lower)& (train_set$y < Upper),]

# Functions ---------------------------------------------------------------

# Function used to compute the feature matrix
power_functions <- function(d, q, knots, x){
  X <- matrix(NA, length(x), d+q+1)
  for( i in 1:length(x)){
    
    for(j in 1:(d+q+1)){
      
      if ( j <= d+1){
        X[i,j] <- x[i]^(j-1)
      }
      
      else
        if((x[i] - knots[j-(d+1)])^d > 0){
          X[i,j] <- (x[i] - knots[j-(d+1)])^d 
        }
      else 
        X[i,j] <- 0
    }
  }
  return(X)
}


# Function to estimate the weights
compute_weights <- function(knots , dataset){
  n <- length(knots)
  knots <- c(0, knots)
  
  if(knots[(n+1)] != 1){
    knots <- c(knots, 1)
  }
  
  xx <- rep(NA, length(dataset$x))
  v <- 1

  # compute the variance
  for(i in 1:(n+1)){
    if(sum(dataset$x >= knots[i] & dataset$x <= knots[i+1])>1){
      v  <- var(dataset$y[(dataset$x >= knots[i]) & (dataset$x <= knots[i+1])])
      xx[dataset$x >= knots[i] & dataset$x <= knots[i+1]] <- 1 / v
    }
    else if(sum(dataset$x >= knots[i] & dataset$x <= knots[i+1]) == 1){
      xx[dataset$x >= knots[i] & dataset$x <= knots[i+1]] <- 1/v
    }
  }
  
  return(xx)
}


# Function used for the cross validation
cross_val_func <- function(x){
  set.seed(0707020)
  d <- x[1]
  q <- x[2]
  k <- x[3]
  a <- x[4]
  l <- x[5] 
  p <- x[6]
  
  # size of the fold
  l_folds <- nrow(train_set) / k 
  idx <- sample((1:nrow(train_set)),nrow(train_set))
  score <- rep(NA, k)
  
  for ( i in 1:k){
    cv_test <- train_set[idx[((i-1)*l_folds+1): (i*l_folds)],]
    cv_train <- train_set[-idx[((i-1)*l_folds+1): (i*l_folds)],]
    
    #knots <- seq(1/q, p, length.out=q) #knots unif
    knots <- seq(0, p, length.out=q+1)[2:(q+1)] # knots first part
    
    M_cv_train <- power_functions(d = d, q = q, knots = knots, x = cv_train$x)
    # M_cv_train <- data.frame(M_cv_train , target = cv_train$y)
    
    M_cv_test <-  power_functions(d = d, q = q, knots = knots, x = cv_test$x)

    hat_weights <- compute_weights(knots = knots , cv_train)
    
    cv_model <- glmnet(M_cv_train, 
                       cv_train$y,
                       family = "gaussian", 
                       alpha=a, 
                       lambda=l,
                       weights = hat_weights)
    
    cv_predictions <- predict(cv_model, M_cv_test)
    
    score[i] <- sqrt(mean((cv_test$y-cv_predictions)^2))
    
  }
  return(mean(score))
}


# Secondary function for nested CV
inner_crossval <- function(x, train_set){
  d <- x[1]
  q <- x[2]
  K <- x[3]
  a <- x[4]
  l <- x[5] 
  p <- x[6]
  
  e_in <- c()
  
  for(k in (1:(K-1))){
    idx <- ((k-1)*l_folds+1): (k*l_folds)
    cv_test <- train_set[idx,]
    cv_train <- train_set[-idx,]
    
    knots <- seq(0, p, length.out=q+1)[2:(q+1)]
    
    M_cv_train <- power_functions(d = d, q = q, knots = knots, x = cv_train$x)
    M_cv_test <-  power_functions(d = d, q = q, knots = knots, x = cv_test$x)
    
    hat_weights <- compute_weights(knots = knots , cv_train)
      
    cv_model <- glmnet(M_cv_train, 
                       cv_train$y,
                       family = "gaussian", 
                       alpha=a, 
                       lambda=l,
                       weights = hat_weights)
    
    cv_predictions <- predict(cv_model, M_cv_test)
    
    e_temp <- sqrt((cv_test$y-cv_predictions)^2)
    e_in <- c(e_in, e_temp)
  }
  
  return(e_in)
}

# Main function for the nested CV
nested_crossval <- function(x){
  d <- x[1]
  q <- x[2]
  K <- x[3]
  a <- x[4]
  l <- x[5] 
  p <- x[6]
  R <- 250
  #R <- 5
  l_folds <<- nrow(train_set) / K
  
  es <- c()
  a_list <- rep(NA, R*K)
  b_list <- rep(NA, R*K)
  for(r in (1:R)){
    idx <- sample((1:nrow(train_set)),nrow(train_set))
    
    for(k in (1:K)){  
      cv_test <- train_set[idx[((k-1)*l_folds+1): (k*l_folds)],]
      cv_train <- train_set[-idx[((k-1)*l_folds+1): (k*l_folds)],]
      
      # inner cross
      e_in <- inner_crossval(x, cv_train)
      
      # Outer cross
      knots <- seq(0, p, length.out=q+1)[2:(q+1)]
     
      M_cv_train <- power_functions(d = d, q = q, knots = knots, x = cv_train$x)
      M_cv_test <-  power_functions(d = d, q = q, knots = knots, x = cv_test$x)
      
      hat_weights <- compute_weights(knots = knots , cv_train)
      
      cv_model <- glmnet(M_cv_train, 
                         cv_train$y,
                         family = "gaussian", 
                         alpha=a, 
                         lambda=l,
                         weights = hat_weights)
      
      cv_predictions <- predict(cv_model, M_cv_test)
      
      e_out <- sqrt((cv_test$y-cv_predictions)^2)
      
      es <- c(es, e_in)
      a_list[(r-1)*K+k] <- (mean(e_in)-mean(e_out))^2 
      b_list[(r-1)*K+k] <- (sd(e_out)^2)/l_folds
    }
  }
 
  mse <- abs(mean(a_list)-mean(b_list))
  err <- mean(es)
  
  return(paste(mse, err))
}



# Parameters -------------------------------------------------------------
k <- c(5)
d_grid <- c(1, 3) 
q_grid <- seq(3, 50, 2)
positions <- seq(0.2, 0.8, 0.1)
lambdas <- 10^seq(-0.5, 0, .05)
alphas <- seq(0, 1, 0.1)
# Set the parameter for the CV
parameters <- list(d_grid, q_grid, k, alphas, lambdas, positions)

# CV vanilla --------------------------------------------------------------
# Select the best combination of parameters
cl = makeCluster(detectCores())
clusterExport(cl, c('train_set', 'power_functions', 'glmnet', 'compute_weights'))
res <- gridSearch(cross_val_func, levels=parameters, method = 'snow', cl=cl)
stopCluster(cl)
best_params <- res$minlevels
names(best_params) <- c('d', 'q', 'k', 'alpha', 'lambda', 'position')
save(best_params, "RData\best_params_vanilla_NODC.RData")
# Update Parameters -------------------------------------------------------------
load("RData\\best_params_vanilla_NODC.RData")
# Using the best parameters
d_best <- best_params[1]
q_best <- best_params[2]
k_best <- best_params[3]
a_best <- best_params[4]
l_best <- best_params[5]
p_best <- best_params[6]

d <- d_best
q <- q_best + seq(-1,1,1)
k <- k_best
a <- a_best + seq(-0.03, 0, 0.01)
l <- l_best + seq(-0.05, 0.05, 0.025)
p <- p_best 

# Set the parameter for the CV
parameters <- list(d, q, k, a, l, p)

# CV nested --------------------------------------------------------------
cl = makeCluster(detectCores())
clusterExport(cl, c('train_set','compute_weights' ,'inner_crossval', 'power_functions', 'glmnet'))
res <- gridSearch(nested_crossval, levels=parameters, method = 'snow', cl=cl)
stopCluster(cl)
best_params <- res$minlevels
names(best_params) <- c('d', 'q', 'k', 'alpha', 'lambda','position')


# plot errors 
return_numeric <- function(x){
  return(as.numeric(strsplit(x, ' ')[[1]]))
} 

write.csv(data.frame(mse,err), "RData/Nested_NODC.csv", row.names=FALSE)
vector <- unlist(lapply(res$values, FUN = return_numeric))
n <- length(vector)

mse <- sqrt(vector[seq(n) %% 2 == 1])*1.96
err <- vector[seq(n) %% 2 == 0]

ggplot()+geom_line(aes(x=1:length(mse),y=err))+
  geom_errorbar(aes(x =1:length(mse), ymin=err-mse,ymax=mse+err,width=0.2, color='red'))


# Prediction --------------------------------------------------------------

# Using the best parameters
d_best <- best_params[1]
q_best <- best_params[2]
k_best <- best_params[3]
a_best <- best_params[4]
l_best <- best_params[5]
p_best <- best_params[6]

# Compute the predictions
knots <- seq(0, p_best, length.out=q_best+1)[2:(q_best+1)]
M_train <- power_functions(d = d_best, q = q_best, knots = knots, x = train_set$x)
M_test <- power_functions( d = d_best, q = q_best, knots = knots, x = test_set_vero$x)
knots_test <- power_functions( d = d_best, q = q_best, knots = knots, x = knots)
hat_weights <- compute_weights(knots , train_set)
final_model <- glmnet(M_train, train_set$y, family ="gaussian", 
                      alpha=a_best, lambda=l_best , weights = hat_weights )
predictions <- predict(final_model,M_test)



# Plot --------------------------------------------------------------------

# Simple plot
plot(train_set$x,train_set$y,cex = .5, pch = 16, col = "Green")
points(test_set_vero$x,predictions, col = "orange", cex = .5, pch=16)
grid()
points(knots, predict(final_model, knots_test), col='red', pch=3, cex=1, lwd=4)



# install.packages('tidyverse')
# install.packages('manipulate')
# 
# library(tidyverse)
# library(manipulate)
# 
# colors <- c("Real Data" = "green", "Predicted" = "blue", "Knots" = "red")
# green_point_size <- 1.3
# blue_point_size <- 1.3
# red_cross_size <- 2
# 
# plot_fun <- function(x_min, x_max){
#   ggplot() +
#     geom_point(aes(x = train_set$x, y = train_set$y, color = 'Real Data'), size = green_point_size, shape=16) +
#     geom_point(aes(x = test_set_vero$x, y = predictions, color = 'Predicted'), size = blue_point_size) +
#     geom_point(aes(x = knots, y = predict(final_model, knots_test), color = 'Knots'), shape = 4, stroke = 1.7, size = red_cross_size) +
#     theme_minimal() +
#     labs(x = "x", y = "y", color = "Legend", title = 'Prediction on WMAP data', shape = "", color="") +
#     scale_color_manual(values = colors) +
#     theme(legend.title = element_text(size=12), legend.text = element_text(size=11), plot.title = element_text(hjust = 0.5)) +
#     coord_cartesian(xlim = c(x_min, x_max))+
#     guides(color = guide_legend(override.aes=list(shape = c(4, 16, 16), size = 2)))}
# 
# manipulate(plot_fun(x.min, x.max), x.min = slider(0,.9, 0, step = .1), x.max = slider(.1, 1, 1, step = .1))
# 



# Output ------------------------------------------------------------------
# 1.00, 40.00, 4.00, 0.77, 1.05, 0.70  Best parameters with data cleaning
# save(best_params, file = "RData/best_params_DC")

# 3.00, 45.00, 5.00, 1.00, 0.86, 0.60, Best parameters w/o data cleaning
# save(best_params, file = "RData/best_params_NODC")


dataset <- data.frame(id = test_set_vero$id, daje = predictions)
colnames(dataset) <- c("id", "target")

# With data cleaning
# write.csv(dataset, "preds/predictions_DC.csv", row.names=FALSE) 
# pp <- read.csv("preds/predictions_DC.csv")

# Without data cleaning
# write.csv(dataset, "preds/predictions_NODC.csv", row.names=FALSE)
# pp <- read.csv("preds/predictions_NODC.csv")

plot(test_set_vero$x , pp$target)

write.csv(dataset, "preds/predictions.csv", row.names=FALSE)

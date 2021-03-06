MFVAR <-
function(monthly, quarterly, p=3, prior="default") {
  
  # Restricted options for MFVAR
  type="const"
  dummy=NULL

  #------------------- FORMAT DATA -------------------#

  # Breadth of monthly and quarterly data 
  Kq <- NCOL(quarterly)
  Km <- NCOL(monthly)
  # Start month of quarterly data (2 months prior to "starting quarter")
  month.start <- c(floor(tsp(quarterly)[1]), tsp(quarterly)[1]%%1*12+1)
  # Create quarterly and monthly observation time series
  xq <- ts(matrix(rep(quarterly,each=3),NROW(quarterly)*3,Kq), 
           frequency = 12, 
           start = month.start)
  xm <- monthly
  # Data for estimating the initial VAR parameters
  y.init <- na.omit(cbind(xm, xq))
  colnames(y.init) <- c(colnames(monthly), colnames(quarterly))
  # Insert NA for unobserved data
  for(i in 1:nrow(xq)) if(i%%3 != 0) xq[i,] <- NA
  # Combine monthly and quarterly time series
  x <- cbind(xm, xq)
  colnames(x) <- c(colnames(monthly), colnames(quarterly))

  #------------------- 'TRAINING DATA' MEAN AND VARIANCE FOR PRIOR -------------------#

  # number of variables
  K <- ncol(y.init)
  # Determine cut-off date for training data (10%)
  # NB! this also ensures that the data for estimation always starts on the
  # first month of a quarter (rest of code assumes this!)
  dates   <- time(y.init)
  cut.off <- c(floor(dates[ceiling(length(dates)*0.1)])-1,12)
  # Training data
  YY <- window(y.init, end=cut.off)
  # Sample means
  mu <- apply(YY,2,mean)
  # Variances of error terms from AR(1) regressions
  sigma <- rep(NA,K)
  for(i in 1:K) {
    yy  <- YY[2:nrow(YY),i]
    xx  <- cbind(1, YY[1:(nrow(YY)-1),i])
    b0 <- solve(crossprod(xx), crossprod(xx,yy))
    sigma[i] <- sqrt(crossprod(yy-xx%*%b0) / (NROW(yy)-2))
  }
  # Remove training data from dataset
  x      <- window(x, start=cut.off+c(0,1))
  y.init <- window(y.init, start=cut.off+c(0,1))
  # Create a prior for starting state (Kalman Filter) from training data
  y1 <- as.matrix(c(1,as.vector(t(YY[(nrow(YY)-p+1):nrow(YY),]))))

  #------------------- CREATE OBSERVATION ARRAY -------------------#

  # Typical quarterly, monthly, and combined observation matrix
  L_qz <- matrix(rep(cbind(matrix(0,Kq,Km),diag(1/3,Kq)),3),Kq,Km*3+Kq*3)
  L_mz <- cbind(diag(Km),matrix(0,Km,Km*2+Kq*3))
  L_z  <- cbind(matrix(0,Kq+Km,1), rbind(L_mz,L_qz))
  # Allowance for VAR of order more than 3
  if(p > 3) L_z <- cbind(L_z,matrix(0,Kq+Km,(Kq+Km)*(p-3)))
  # Time varying observation array (allowing for unobserved data)
  ML_z <- array(L_z, dim=c(dim(L_z),nrow(x))) 
  # Create (column) indices for "unobserved observations"
  na.index.xm <- which(is.na(apply(x[,1:Km,drop=FALSE],1,prod)))
  na.index.xq <- which(is.na(apply(x[,(Km+1):(Km+Kq),drop=FALSE],1,prod)))
  # Replace all NAs with zero
  x[is.na(x)] <- 0
  # Replace transform on quarterly variables (L_qz) with zero where data unobserved
  for(i in na.index.xq) {
    if(i%%3 == 0)
      ML_z[Km+which(!(abs(x[i,(Km+1):(Km+Kq)])>0)),,i] <- 0
    else
      ML_z[(Km+1):(Km+Kq),,i] <- 0
  }
  # Replace transform on monthly variables (L_mz) with zero where data unobserved
  if(length(na.index.xm)>0) 
    for(i in na.index.xm) 
      ML_z[which(!(abs(x[i,1:Km])>0)),,i] <- 0

  #-------------- OLS ESTIMATES OF INITIAL STATE (VAR) MATRICES --------------#
   
  # Construct Z for Y = ZB + U
  z <- as.matrix(y.init) 
  Z <- matrix(NA, nrow=nrow(z)-p, ncol=K*p) 
  # Create new data matrix with p lags for all the variables
  for(i in 1:p) Z[, (K*(i-1) + 1):(K*i) ] <- z[((p+1) - i):(nrow(z) - i), ]
  # Constant (dd) and number of deterministic variables
  dd <- as.matrix(rep(1,nrow(z)))
  M  <- NCOL(dd) 
  # adjust data for lags
  Y <- z[(p+1):nrow(z),]
  Z <- cbind(dd[(p+1):nrow(z),],Z)
  # OLS estimate
  B  <- solve.qr(qr(Z),Y)
  # VAR (companion) matrices
  Acomp <- rbind(c(1,rep(0,K*p)),t(B), 
    cbind(rep(0,K*(p-1)),diag(K*(p-1)),matrix(0,K*(p-1),K)))
  Scomp <- matrix(0,K*p+M, K*p+M)
  Scomp[(M+1):(K+M),(M+1):(K+M)] <- crossprod(Y-Z%*%B)/(nrow(Y)-M-K*p)

  #------------------- DUMMY DATA FOR BVAR -------------------#
  
  # artificial data
  YD <- NULL
  ZD <- NULL
  # artificial data for Minnesota prior
  if(any(prior$prior=="mn")) {
    m1 <- diag(sigma)
    m2 <- matrix(0,K*(p-1),K)
    m3 <- matrix(0,M,K)
    m4 <- matrix(0,K*p,M)
    m5 <- t(m3)
    m6 <- diag(M)
    m7 <- t(m4)
    m8 <- diag(1:p)
    m9 <- matrix(0,K,K*p)
    YD <- rbind(prior$hp$lambda*m1*(1/prior$hp$tau), m2, m1, m3)
    ZD <- cbind(rbind(m4, m5, m6/prior$hp$kappa),
                rbind((m8^prior$hp$rho)%x%m1*(1/prior$hp$tau), m9, m7))
  }
  # artificial data for sum of coefficients prior
  if(any(prior$prior=="sc")) {
    m1 <- diag(mu)
    m2 <- matrix(0,K,M)
    m3 <- matrix(rep(1,p),1,p)
    YD <- rbind(YD, prior$hp$lambda*m1/prior$hp$gamma)
    ZD <- rbind(ZD, cbind(m2,m3%x%(prior$hp$lambda*m1/prior$hp$gamma)))
  }
  # artificial data for common stochastic trends prior
  if(any(prior$prior=="st")) {
    m1 <- c(1,rep(0,M-1))
    YD <- rbind(YD, prior$hp$delta*mu)
    ZD <- rbind(ZD, prior$hp$delta*c(m1, rep(mu,p)))
  }

  #------------------- OUTPUT -------------------#
  
  out <- list("obs"=x,
              "lag"=p,
              "filtmat"=list("ML_z"=ML_z,"Acomp"=Acomp,"Scomp"=Scomp,"y1"=y1),
              "dummy"=list("YD"=YD,"ZD"=ZD))
  class(out) <- "MFVAR model"
  return(out)
}

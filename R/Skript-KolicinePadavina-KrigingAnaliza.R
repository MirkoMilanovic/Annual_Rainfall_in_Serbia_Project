# podešavanje radnog direktorijuma
setwd("C:/Users/Mirko/Desktop/GEOST. PROJ/R")

# podešavanje polaznih parametara
options(prompt="> ", continue="+ ", digits=8, width=70, show.signif.stars=T)
# ucitavanje paketa
library(sp)
library(rgdal)
library(gstat)
library(rgeos)
library(foreign)
library(ggplot2)

# ucitavanje tabele datih podataka
podaci <- read.table(file="podaci.txt", header=TRUE, sep="\t", dec=".", na.strings=c("NA", "-", "?"))

# histogram zavisnosti broja stanica od registrovane kolicine padavina u toku 2016. godine
hist(podaci$PADAVINE, xlab="Suma padavine u 2016. god. (mm)", col="yellow", main="Zavisnost broja klimatoloških stanica od registrovane kolicine padavina na njima u 2016. godini")

# kopiranje datih podataka i transformacija koordinata
podaci1 = podaci
coordinates(podaci1) <- c("DUZINA", "SIRINA")
proj4string(podaci1) <- CRS("+init=epsg:4326")
podaci1 <- spTransform(podaci1, CRS("+proj=tmerc +lat_0=0 +lon_0=21 +k=0.9999 +x_0=7500000 
                                                           +y_0=0 +ellps=bessel 
                                                           +towgs84=577.326,90.129,463.919,5.137,1.474,5.297,2.4232   						 +units=m +no_defs"))


# bubble plot registrovane kolicine padavina na klimatološkim stanicama
bubble(subset(podaci1,!is.na(PADAVINE)), scales=list(draw=T), "PADAVINE",  col="red", pch=15, maxsize=2)

# ucitavanje rastera DEM Republike Srbije
dem <- readGDAL("SrbijaDEM.tif")

# prostorno povezivanje podataka (tacke i grid)
podaci11 = over(podaci1, dem)
podaci1@data <- cbind(podaci11, podaci1@data)

# pozicije klimatoloških stanica na podlozi DEM Pepublike Srbije prikazane topografskom paletom boja
plot(dem, main="Pozicije klimatoloških stanica", col=topo.colors(20))
points(subset(podaci1, !is.na(PADAVINE)), col ="red" , pch = 17)



# regresija, aproksimaciona kriva zavisnosti nadmorske visine stanica od registrovanih padavina na njima
scatter.smooth(podaci1$VISINA, podaci1$PADAVINE, col="blue", xlab="Nadmorska visina (m)", ylab="Padavine (mm)")

# fitovanje linearnog modela
fit <- lm(PADAVINE ~ band1, podaci1)
# linear prediction
prediction <- predict(fit, podaci1)
# remove NA values for PADAVINE and unnecessary variables
drops <- c("VISINA")
podaci1 <- podaci1[,!(names(podaci1) %in% drops)]
podaci1 <- podaci1[!(is.na(podaci1$PADAVINE)),]

# interpolacija metodom inverznih distanci
PADAVINE.idw <- idw(PADAVINE ~ 1, podaci1, dem, idp = 2.5)
# variogram model
n <- vgm(nugget=0, model="Exp", range=sqrt(diff(podaci1@bbox["DUZINA",])^2 + diff(podaci1@bbox["SIRINA",])^2)/4, psill=var(podaci1$PADAVINE))

# ordinary kriging
PADAVINE.ordinary <- krige(PADAVINE ~1, podaci1, dem, model= n)
spplot(PADAVINE.ordinary["var1.pred"], main = "ordinary kriging predictions")

# simple kriging
PADAVINE.simple <- krige(PADAVINE ~1, podaci1, dem, model = n, beta = 5)
spplot(PADAVINE.simple["var1.pred"], main = "simple kriging predictions")

# variogram za block kriging
v = variogram(PADAVINE~band1, podaci1)
m <- vgm(nugget=0, model="Gau", range=sqrt(diff(podaci1@bbox["DUZINA",])^2 + diff(podaci1@bbox["SIRINA",])^2)/4, psill=var(residuals(fit)))
fitv = fit.variogram(v, m)
plot(v,m)

# universal block kriging
PADAVINE.block <- krige(PADAVINE ~band1, podaci1, dem, block = c(40,40), model=fitv)
spplot(PADAVINE.block["var1.pred"], main = "block kriging predictions")
spplot(PADAVINE.block["var1.var"],  main = "block kriging variance")




# standardne greške za sve kriging metode 
mean(sqrt(PADAVINE.ordinary$var1.var), na.rm = TRUE)
mean(sqrt(PADAVINE.simple$var1.var), na.rm = TRUE)
mean(sqrt(PADAVINE.block$var1.var), na.rm = TRUE)

# extraktovanje rastera predikcije
writeGDAL(PADAVINE.block["var1.pred"], "C:/Users/Mirko/Desktop/GEOST. PROJ/R/predicted.tif", drivername="GTiff")


# kopiranje ulaznih podataka, transformacija koordinata i prostorno preklapanje podataka
podaci2 = podaci
coordinates(podaci2) <- c("DUZINA", "SIRINA")
proj4string(podaci2) <- CRS("+init=epsg:4326")
podaci2 <- spTransform(podaci2, CRS("+proj=tmerc +lat_0=0 +lon_0=21 +k=0.9999 +x_0=7500000 
                                                           +y_0=0 +ellps=bessel 
                                                           +towgs84=577.326,90.129,463.919,5.137,1.474,5.297,2.4232   					 +units=m +no_defs"))

idw <- over(podaci2, PADAVINE.idw)
ordinary <- over(podaci2, PADAVINE.ordinary)
simple <- over(podaci2, PADAVINE.simple)
block <- over(podaci2, PADAVINE.block)

podaci2 <- podaci2[,!(names(podaci2) %in% drops)]
View(podaci2)

# dodavanje vrednosti u tabelu sa stanicama
podaci2$lm <- prediction
podaci2$idw <- idw$var1.pred
podaci2$ord <- ordinary$var1.pred
podaci2$simp <- simple$var1.pred
podaci2$block <- block$var1.pred

podaci2 <- podaci2[,!(names(podaci2) %in% drops)]
View(podaci2)

# bubble plot registrovanih i procenjenih kolicine padavina na stanicama i traženim mestima
bubble(podaci2, "block", scales=list(draw=T), col="red", pch=15, maxsize=2)

# dodavanje procenjenih padavina u tabelu sa podacima za tražena mesta (40.-46. reda u tabeli)
podaci2 <- as.data.frame(podaci2)
podaci2[, 2][is.na(podaci2[, 2])] <- block[40:46, 1]
podaci2$PADAVINE[podaci2$PADAVINE < 0] <- 0

# histogram zavisnosti broja lokacija od registrovane i procenjene kolicine padavina u toku 2016. godine
hist(podaci2$PADAVINE, xlab="Suma padavine u 2016. god. (mm)", col="yellow", main="Zavisnost broja stanica i lokacija od interesa od registrovane i procenjene kolicine padavina na njima u 2016. godini")



# formiranje i ekstrakcija tabele sa poznatim i dobijenim vrednostima padavina, konacni podaci
podaci2$H <- podaci$VISINA
podaci2 <- podaci2[c("STANICA", "DUZINA", "SIRINA", "H", "PADAVINE")]
names(podaci2)[names(podaci2)=="DUZINA"] <- "Y"
names(podaci2)[names(podaci2)=="SIRINA"] <- "X"
View(podaci2)
write.table(podaci2, "podaciNovo.txt", sep="\t", row.names = FALSE)



# HIJERARHIJSKO KLASIRANJE
#kopiranje polaznih podataka
podaci3 = podaci2

# brisanje nepotrebnih kolona
podaci3$Y = NULL
podaci3$X = NULL
View(podaci3)

# racunanje Euklidskih distanci
distances = dist(podaci3[,2:3], method = "euclidean")

# hijerarhijsko klasiranje
cluster = hclust(distances, method = "ward.D")

# plot dendrograma
plot(cluster)

# dodeljivanje tacaka formiranim klasama
clusterGroups = cutree(cluster, k = 5)

# pretraga u kojoj klasi se nalazi stanica SABAC
subset(podaci3, STANICA=="SABAC")
clusterGroups[42]

# kreiranje novog seta podataka sa stanicama koje pripadaju samo klasama 1 i 5
cluster1 = subset(podaci3, clusterGroups==1)
cluster5 = subset(podaci3, clusterGroups==5)

# ispis stanica koje pripadaju klasama 1 i 5
cluster1$STANICA
cluster5$STANICA


# KLASIFIKACIJA METODOM K-SREDINA
#kopiranje polaznih podataka (samo kolone VISINA i PADAVINE)
podaci4 = podaci2[, 4:5]

# Klasifikacija metodom k-sredina sa 5 klasa i sa 10 iteracija
km <- kmeans(podaci4, 5, 10)
km

# plot koji pokazuje koja stanica pripada kojoj klasi
plot(km$cluster, col = "blue", pch = 16)

# plot centara klastera
plot(km$centers, col = 1:5, pch = 4)

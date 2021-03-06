# R script to
#  - read in ring increment data
#  - merge with plot/core data
#  - compute size versus RWI by plot and species
#  - save

# Ben Bond-Lamberty December 2014

# Support functions and common definitions
source("../0-functions.R")

SCRIPTNAME        <- "2-npp.R"

INCREMENT_MODELS    <- "../tree_cores/outputs/increment_models.csv"
TREE_SURVEY         <- "tree_survey.csv"

# -----------------------------------------------------------------------------
# Packages and reproducibility

#library(checkpoint)  # version 0.3.8
#checkpoint("2015-05-15")
library(dplyr)
library(ggplot2)
theme_set(theme_bw())

# ==============================================================================
# Main

sink(paste(LOG_DIR, paste0(SCRIPTNAME, ".txt"), sep="/"), split=T)

printlog("Welcome to", SCRIPTNAME)

increment_models <- read_csv(INCREMENT_MODELS)
tree_survey <- read_csv(TREE_SURVEY)
printdims(tree_survey)
tree_survey$Notes <- NULL
printlog("Eliminating dead trees...")
tree_survey <- subset(tree_survey, Status=="Alive")
printdims(tree_survey)

printlog("Merging tree survey data with increment models from coring...")
d <- merge(tree_survey, increment_models, by=c("Position_m", "Species"), all=TRUE)

# Allometry coefficients from Alexander et al. (2012), http://dx.doi.org/10.1890/ES11-00364.1
allometry <- read_csv("allometry//Alexander_2012_Appendix_A.csv", comment.char="#")
allometry_larix <- read_csv("allometry//Bond-Lamberty_2002_Larix.csv")  # since Alexander et al. don't include Larix
allometry <- rbind(allometry, allometry_larix)
allometry$Biomass_a <- allometry$DBH_a
allometry$Biomass_a[is.na(allometry$Biomass_a)] <- allometry$D0_a[is.na(allometry$Biomass_a)] # fall back to D0 if not available
allometry$Biomass_b <- allometry$DBH_b
allometry$Biomass_b[is.na(allometry$Biomass_b)] <- allometry$D0_b[is.na(allometry$Biomass_b)] # fall back to D0 if not available
allometry <- allometry[c("Component", "Species", "Biomass_a", "Biomass_b")]

# Make some changes to the allometry table so it matches our data
allometry$Species[allometry$Species == "BENE"] <- "BEPA"  # Paper birch names
allometry <- allometry[allometry$Component == "Total biomass",] # only total biomass

# We recorded all spruce as "PIMA" (Picea mariana, black spruce), but the largest 
# trees are actually white spruce. Looks like 10 cm is a reasonable cutoff; change
printlog("NOTE we are treating all PIMA (black spruce) >10 cm DBH as PIGL (white spruce)")
d$Species[d$Species == "PIMA" & d$DBH_cm > 12] <- "PIGL"

printlog("Merging survey data with allometry...")
d <- merge(d, allometry)

printlog("Computing increments...")
d$Increment_mm <- with(d, DBH_cm * m + b)
d$DBH_old <- with(d, DBH_cm - 2 * Increment_mm / 10.0)

printlog("Computing biomass...")
d$Biomass <- with(d, Biomass_a * DBH_cm ^ Biomass_b)
d$Biomass_old <- with(d, Biomass_a * DBH_old ^ Biomass_b)

printlog("Computing NPP...")
npp <- d %>%
    group_by(Transect, Position_m) %>%
    summarise(npp_gC=sum(Biomass, na.rm=T) - sum(Biomass_old, na.rm=T))
npp$Transect <- factor(npp$Transect, levels=c("T5", "T6", "T7", "T8", "T9", "T10"))

# Change to final units
plotsize <- 5 ^ 2 * pi / 2   # plotsize, semicircle w/ radius of 5 m
npp$npp_gC <- npp$npp_gC / plotsize
npp$npp_gC <- npp$npp_gC / 2.0  # to grams biomass to grams C

print(summary(npp))
save_data(npp, scriptfolder=FALSE)

stop('ok')


# TODO: clean up

# Fit an NPP variogram?

# Get transect position data
transects <- read_csv("../transects/CPCRW_2014_Transect_Positions.csv")
transects$Transect <- paste0("T", transects$Transect)
npp <- merge(npp, transects)

library(gstat)

vgm <- variogram(log(npp_gC)~1, ~Position_m + Position.S.to.N_m, npp)



printlog("Plotting...")

p1 <- ggplot(npp, aes(Transect, Position_m)) + geom_tile(aes(fill=npp_gC))
p1 <- p1 + ylab("Transect position (m)") + xlab("Transect")
p1 <- p1 + scale_fill_continuous("NPP (gC/m2/yr)")
print(p1)
#save_plot("npp1")

p2 <- ggplot(npp, aes(factor(Position_m), npp_gC)) + geom_boxplot()
p2 <- p2 + xlab("Transect position (m)") + ylab("NPP (gC/m2/yr)")
print(p2)
#save_plot("npp2")


# Species-specific
printlog("Doing species-specific plots...")

npp_species <- d %>%
    group_by(Transect, Position_m, Species) %>%
    summarise(npp_gC=sum(Biomass, na.rm=T) - sum(Biomass_old, na.rm=T))

npp_species$npp_gC <- npp_species$npp_gC / plotsize
npp_species$npp_gC <- npp_species$npp_gC / 2.0  # to g C

# ...and finally take mean of transects!
npp_species <- npp_species %>%
    group_by(Position_m, Species) %>%
    summarise(npp_gC=mean(npp_gC))

p3 <- ggplot(npp_species, aes(factor(Position_m), npp_gC, fill=Species, group=Species)) + geom_bar(stat='identity')
p3 <- p3 + xlab("Transect position (m)") + ylab("NPP (gC/m2/yr)")
print(p3)
#save_plot("npp3")


printlog("All done with", SCRIPTNAME)
print(sessionInfo())
sink()

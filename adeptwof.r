######################################### CONFIGURATION & LIBRARIES #########################################
# Install libraries if necessary and load them into the environment
if (suppressWarnings(require("RPostgreSQL"))==FALSE) {
    install.packages("RPostgreSQL",repos="https://cran.microsoft.com/");
    library("RPostgreSQL");
    }

if (suppressWarnings(require("velociraptr"))==FALSE) {
    install.packages("velociraptr",repos="https://cran.microsoft.com/");
    library("velociraptr");
    }

# This won't be necessary once velociraptr is fixed to use sf
if (suppressWarnings(require("sf"))==FALSE) {
    install.packages("sf",repos="https://cran.microsoft.com/");
    library("sf");
    }

if (suppressWarnings(require("jsonlite"))==FALSE) {
    install.packages("jsonlite",repos="https://cran.microsoft.com/");
    library("jsonlite");
    }

if (suppressWarnings(require("pbapply"))==FALSE) {
    install.packages("pbapply",repos="https://cran.microsoft.com/");
    library("pbapply");
    }

# Establish postgresql connection
# This assume that you already have a postgres instance with PostGIS installed and a database named mapzen
# and that you have comparable configuration and credentials
# This could theoretically be done entirely within R, as the sf packae ports most geoprocessing functions
# from postgis entirely into R, but the benefit of doing it in postgis is because that allows me to preserve
# a stable database rather than recreating data constantly 
Driver<-dbDriver("PostgreSQL") # Establish database driver
Ecos<-dbConnect(Driver, dbname = "mapzen", host = "localhost", port = 5432, user = "zaffos")

# Change the maximum timeout t0 300 second. This will allow you to download larger datafiles from 
# the paleobiology database.
options(timeout=600)

# Functions are camelCase. Variables and Data Structures are PascalCase
# Fields generally follow snake_case for better SQL compatibility
# Dependency functions are not embedded in master functions
# []-notation is used wherever possible, and $-notation is avoided.
# []-notation is slower, but is explicit about dimension and works for atomic vectors
# External packages are explicitly invoked per function with :: operator
# Explict package calls are not required in most cases, but are helpful in tutorials

#############################################################################################################
########################################### DOWNLOAD WOF DATASE, GET ########################################
#############################################################################################################
# A simple function for reading in the geojson
readGeojson = function(path=Metadata$path,header) {
    File = paste0(header,path)
    Geometry = st_read(File,quiet=TRUE)
    Geometry = st_as_text(st_geometry(Geometry))
    return(Geometry)
    }

########################################### DOWNLOAD WOF DATASE, GET ########################################

# Download the US WOF database as a TAR bundle, could do this through R, but I chose not to!
# https://data.geocode.earth/wof/dist/bundles/whosonfirst-data-admin-us-latest.tar.bz2
# Can also be found at the following github repo https://github.com/whosonfirst-data/whosonfirst-data-admin-us

# Download the TAR bundle
# download.file("https://data.geocode.earth/wof/dist/bundles/whosonfirst-data-admin-us-latest.tar.bz2",destfile="~/Downloads")
# untar("...")

# Get a list of the files in metadata folder
# Metadata = list.files(path="~/Downloads/whosonfirst-data-admin-us-latest/meta",pattern="*.csv",full.names=TRUE)
# Read them into R and then collapse
# Metadata = do.call(rbind,lapply(Metadata,read.csv))
# Clean it up by removing features without proper names (mostly from some assholes called quattroshapes?)
# Metadata = subset(Metadata,Metadata[,"name"]!="")

# Get the geometries
# geom = sapply(Metadata$path,readGeojson,"~/Downloads/whosonfirst-data-admin-us-latest/data/")
# Metadata = cbind(Metadata,geom)
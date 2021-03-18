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
Mapzen<-dbConnect(Driver, dbname = "mapzen", host = "localhost", port = 5432, user = "zaffos")

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
# Hardcodes a BUNCH of stuff, most notably the database connection parameter
readWOF = function(Path) {
    Initial = sf::st_read(Path,quiet=TRUE)
    # Making the connection internally is for thh paralleized version
    Connection<-RPostgreSQL::dbConnect(DBI::dbDriver("PostgreSQL"), dbname = "mapzen", host = "localhost", port = 5432, user = "zaffos")
    if ("wof.hierarchy"%in%names(Initial)!=TRUE) {RPostgreSQL::dbDisconnect(Connection); return(NA);}
    id = Initial$wof.id
    name = Initial$wof.name
    placetype = Initial$wof.placetype
    macroregion = jsonlite::fromJSON(Initial$wof.hierarchy)$macroregion_id
    region = jsonlite::fromJSON(Initial$wof.hierarchy)$region_id
    macrocounty = jsonlite::fromJSON(Initial$wof.hierarchy)$macrocounty_id
    county = jsonlite::fromJSON(Initial$wof.hierarchy)$county_id
    localadmin = jsonlite::fromJSON(Initial$wof.hierarchy)$localadmin_id
    locality = jsonlite::fromJSON(Initial$wof.hierarchy)$locality_id
    borough = jsonlite::fromJSON(Initial$wof.hierarchy)$borough_id
    neighborhood = jsonlite::fromJSON(Initial$wof.hierarchy)$neighborhood_id
    # I suspect this process of unconverting then converting back the geom could be circumvented by a more intelligent
    # join of some kind, but I don't want to deal with joining data to an sf object...
    geom = unlist(sf::st_as_text(Initial$geometry))
    Flattened = as.data.frame(cbind(id,name,placetype,macroregion,region,macrocounty,county,localadmin,locality,borough,neighborhood,geom),stringsAsFactors=FALSE)  
    Flattened = sf::st_as_sf(Flattened,wkt="geom")
    # Write them to the WOF table
    sf::st_write(dsn=Connection,obj=Flattened,"usa_wof",append=TRUE,row.names=FALSE)
    # Need to close the connection 
    RPostgreSQL::dbDisconnect(Connection)
    return(id)
    }

########################################### DOWNLOAD WOF DATASE, GET ########################################
# Download the US WOF database as a TAR bundle, could do this through R, but I chose not to!
# https://data.geocode.earth/wof/dist/bundles/whosonfirst-data-admin-us-latest.tar.bz2
# Can also be found at the following github repo https://github.com/whosonfirst-data/whosonfirst-data-admin-us

# Download the TAR bundle
# download.file("https://data.geocode.earth/wof/dist/bundles/whosonfirst-data-admin-us-latest.tar.bz2",destfile="~/Downloads")
# untar("...")

# Create the blank table
dbSendQuery(Mapzen,"CREATE TABLE usa_wof (id bigint,name varchar, placetype varchar, macroregion bigint, region bigint, macrocount bigint, county bigint, localadmin bigint, locality bigint, borough bigint, neighborhood bigint, geom geometry)")

# Get a list of the geojsons
Metadata = list.files(path="~/Downloads/whosonfirst-data-admin-us-latest/data",pattern="*.geojson",full.names=TRUE,recursive=TRUE)

# Write them into the postgres database
# Definitely parallelize this if you ever do it again... the i/o is ridic
# Write = pbsapply(Metadata,readWOF,Mapzen)

###### Start Alternative Parallelized Version ######
# If running from UW-Madison
# Load or install the doParallel package
if (suppressWarnings(require("doParallel"))==FALSE) {
        install.packages("doParallel",repos="https://cran.microsoft.com/");
        library("doParallel");
        }

# Start a cluster for multicore, 3 by default or higher if passed as command line argument
Cluster<-makeCluster(3)
clusterExport(cl=Cluster, varlist=c("readWOF"))
# Upload the geojson into 
Output<-parSapply(Cluster,Metadata,readWOF)
# Stop the cluster
stopCluster(Cluster)
###### End Alternative Parallelized Version #######

# Gotta make a god damn index and set a primary key for the love of god
# Could have defined the PKEY when making the table schema a few lines above, but
# We need to eliminate duplicates first... there are a few ways to do it
dbSendQuery(Mapzen,"CREATE TABLE cleaned_usa AS SELECT DISTINCT * FROM usa_wof")
dbSendQuery(Mapzen,"ALTER TABLE cleaned_usa ADD PRIMARY KEY (id);")
dbSendQuery(Mapzen,"CREATE INDEX ON cleaned_usa USING GiST (geom);") # probably not needed since it is point data
dbSendQuery(Mapzen,"VACUUM ANALYZE cleaned_usa;")
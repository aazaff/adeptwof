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

if (suppressWarnings(require("stringr"))==FALSE) {
    install.packages("stringr",repos="https://cran.microsoft.com/");
    library("stringr");
    }

# Establish postgresql connection
# This assume that you already have a postgres instance with PostGIS installed and a database named mapzen
# and that you have comparable configuration and credentials
# This could theoretically be done entirely within R, as the sf packae ports most geoprocessing functions
# from postgis entirely into R, but the benefit of doing it in postgis is because that allows me to preserve
# a stable database rather than recreating data constantly 
Driver = dbDriver("PostgreSQL") # Establish database driver
Mapzen = dbConnect(Driver, dbname = "mapzen", host = "localhost", port = 5432, user = "zaffos")

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
    Connection = RPostgreSQL::dbConnect(DBI::dbDriver("PostgreSQL"), dbname = "mapzen", host = "localhost", port = 5432, user = "zaffos")
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
    sf::st_write(dsn=Connection,obj=Flattened,c("wof","usa_raw"),append=TRUE,row.names=FALSE)
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

# Create the 
# Create the blank table
dbSendQuery(Mapzen,"CREATE TABLE wof.usa_raw (id bigint,name varchar, placetype varchar, macroregion bigint, region bigint, macrocounty bigint, county bigint, localadmin bigint, locality bigint, borough bigint, neighborhood bigint, geom geometry)")

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
Cluster = makeCluster(3)
clusterExport(cl=Cluster, varlist=c("readWOF"))
# Upload the geojson into 
Output = parSapply(Cluster,Metadata,readWOF)
# Stop the cluster
stopCluster(Cluster)
###### End Alternative Parallelized Version #######

# Gotta make a god damn index and set a primary key for the love of god
# Could have defined the PKEY when making the table schema a few lines above, but
# We need to eliminate duplicates first... there are a few ways to do it
dbSendQuery(Mapzen,"CREATE TABLE wof.usa_clean AS SELECT DISTINCT * FROM wof.usa_raw WHERE region>0")
dbSendQuery(Mapzen,"DELETE FROM wof.usa_clean AS A USING wof.usa_clean AS B WHERE A.ctid < B.ctid AND A.id=B.id;")
dbSendQuery(Mapzen,"ALTER TABLE wof.usa_clean ADD PRIMARY KEY (id);")
dbSendQuery(Mapzen,"UPDATE wof.usa_clean SET geom=ST_SetSRID(geom,4326);")
dbSendQuery(Mapzen,"CREATE INDEX ON wof.usa_clean USING GiST (geom);") # probably not needed since it is point data
dbSendQuery(Mapzen,"VACUUM ANALYZE;")

#############################################################################################################
########################################### DOWNLOAD XDD DOCS, GET ##########################################
#############################################################################################################
# Some regex bullshit
cleanSubregions = function(Subregions) {
    Subregions$name = gsub('\\ \\(historical\\)',"",Subregions$name)
    Subregions$name = gsub('[:punct:]',"",Subregions$name)
    Subregions$name = gsub("\\s*(\\([^()]*(?:(?1)[^()]*)*\\))", "", Subregions$name, perl=TRUE)
    Subregions$name = gsub(')',"",Subregions$name)
    return(Subregions)
    }

matchSubregional = function(Text) {
    Regions = dbGetQuery(Mapzen,"SELECT id, name FROM wof.usa_clean WHERE placetype='region'")
    RegionHits = sapply(Regions[,"name"],function(x) sum(stringr::str_count(Text,pattern=x)))
    Regions = Regions[which(RegionHits>0),"id"]
    Query = "SELECT id, name, placetype, county, region FROM wof.usa_clean WHERE placetype!='region' AND region IN ("
    Query = paste0(Query,paste(Regions,collapse=","),');')
    Subregions = dbGetQuery(Mapzen,Query)
    Subregions = cleanSubregions(Subregions)
    # Check for locations hits
    Subregional = pbsapply(Subregions$name,1,function(x) stringr::str_count(Text,pattern=x))
    Result = Subregions[Subregional>0,c("id","name","placetype","county","region")]
    return(Result)
    }

# Initiate a join
matchCounty = function(Locations) {
    Counties = paste(unique(na.omit(Locations$county)),collapse=",")
    Subquery = paste('(SELECT * FROM wof.usa_clean WHERE id IN (',Counties,'))')
    Query = paste("WITH candidates AS",Subquery,"SELECT A.id,A.name,A.placetype,A.region,B.id,B.name,B.placetype,B.region FROM candidates AS A JOIN candidates AS B ON ST_Intersects(ST_MakeValid(A.geom),ST_MakeValid(B.geom)) AND A.id!=B.id")
    Matches = dbGetQuery(Mapzen,Query)
    return(Matches)
    }

########################################## DOWNLOAD XDD DOCS, GET ##########################################
# Get the documents
Documents = jsonlite::fromJSON("https://xdd.wisc.edu/api/products?api_key=5eda7896-602d-4131-9c4b-7241cb7f1f06&products=scienceparse")
Text = Documents$success$data$results$scienceparse$metadata$sections
Metadata = Documents$success$data$results$bibjson

# Select regions
Regions = dbGetQuery(Mapzen,"SELECT id, name FROM wof.usa_clean WHERE placetype='region'")
RegionHits = sapply(Regions[,"name"],function(x) sum(stringr::str_count(Text[[166]][,"text"],pattern=x)))
Regions = Regions[which(RegionHits>0),"id"]
# Test for regions
Locations = dbGetQuery(Mapzen,"SELECT id, name, placetype FROM wof.usa_clean WHERE placetype!='region' AND region IN (85688481, 85688535, 85688579, 85688603, 85688623, 85688641, 85688675, 85688683, 85688701, 85688747)")
# Clar out (historical), ugh
Locations$name = gsub('\\ \\(historical\\)',"",Locations$name)
Locations$name = gsub('[:punct:]',"",Locations$name)
Locations$name = gsub("\\s*(\\([^()]*(?:(?1)[^()]*)*\\))", "", Locations$name, perl=TRUE)
Locations$name = gsub(')',"",Locations$name)
# Check for locations hits
Subregional = apply(Locations,1,function(x) stringr::str_count(Text[[166]][,"text"],pattern=x["name"]))
Subregional = Locations[Subregional>0,c("id","name")]

# Get the "intersects" option
AdjacentLocations = matchConty(paste(unique(Locations[,1]),collapse=","))
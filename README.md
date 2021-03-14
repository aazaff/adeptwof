# ADEPT WOF (Who's on First) Script
This is a simple design document for a potential method of leveraging the [Who's on First](https://github.com/whosonfirst-data/whosonfirst-data) (WOF) gazetteer to classify probable locations in the [XDD library](https://xdd.wisc.edu/).  

## Table of Contnets
+ Resources
    + [Who's on First](#whos-on-first)
    + [XDD](#https://xdd.wisc.edu/)
+ Outline of Steps
    + [Location Named-Entity-Recognition](#location-named-entity-recognition)
    + [Identify Candidate Regions](#identify-candidate-regions)
    + [Model Regions by Parents and Children](#model-regions-by-parents-and-children)
    + [Model Training](#model-training)
    + [Prediction](#prediction)
+ Requirements
 
## Who's on First
[WOF](https://github.com/whosonfirst-data/whosonfirst-data) is a now deprecated gazetteer, a dictionary of geographic locations organized into a hierarchy of parent and child locations. It can be thought of as a competitor to Open Street Map or Geonames. A vital aspect of WOF's design for this project, however, is that every location is associated with its identified parent and child locatiions.

The following simplified (hypothetical) example shows the WOF data structure and how we can use it to quickly infer locations within New York City (e.g., Queens) and locations that New York City is within (e.g., the State of New York). The city of New York, NY would be represented by the third row in this table. 

ID | Name | Country | Region | City | Borough
---- | ---- | ---- | ---- | ---- | ----
01 | USA | 01 | NA | NA | NA
52 | New York | 01 | 52 | NA | NA
187 | New York | 01 | 52 | 187 | NA
387 | Queens | 01 | 52 | 187 | 387
413 | Manhattan | 01 | 52 | 187 | 413
873 | Brooklyn | 01 | 52 |187 | 413

## XDD
[Skipping this description]

## Locations Named-Entity-Recognition
The first step is to identify locations mentioned within XDD documents. There are several ways to approach this. We could either use some sort of NER model (e.g., OpenNLP) or go for a strict string matching approach (i.e., matching every word in the text body of a document versus every named location in WOF)

I am currently interested in pursuing the latter approach for expediency, but there are several potential drawbacks to this approach listed below.
**Q:** How to handle partial string matches or multi-word locations names?
**A:** You cannot, at least not in a robust and satisfactory method. Both of these problems would be ameliorated in an NER model based approach.

**Q** How would you handle the i/o implications of matching two very large vectors?
**A** We have to do some load testing before we know if this is even possible or is a problem. There are a variety of ways that we could try batching up the process to make the footprint smaller. A few ideas off the top of my head include 1) trimming down the WOF to just `name` and `id` field for initial match; 2) doing *limited* nlp pre-processing to only consider nouns (would help with aforementioned multi-word problem); 3) Running the entire thing within PostgreSQL where everything is pre-optimized.

**Q** How would you handle the i/o implications of working with WOF within the CHTC framework - (i.e., moving around different copies of WOF among CHTC nodes)?
**A** The answer to this is currently unclear. Will have to consult with Ian when we get to that stage. I could try standing up WOF as a service somewhere or using its `git` API (more research needed) so that the WOF download and search is done by the web... though I think that would just be a lateral move rather than an improvement in the i/o situation.

## Identify Candidate Regions
This step is straight-forward, for every location matched within WOF (regardless of hierarchy) we extract its relevant parent `region` (if found). So, going back to the aforementioned New York, NY [example](#whos-on-first), if we match `873, Brooklyn` in our document, then we would extract `52, New York` as a candidate region.

## Model Regions by Parents and Children
We then look at all of our candidate regions and construct the following model.

[TRUE/FALSE] ~ b0*(#parent country mentions) + b1*(#adjacent regions) + b2*(#child city mentions) + b3*(#child location mentions)

Presumably this model is going to be some form of logistic regression or an analog. Once we've gotten this far (or actually once we've gotten some training data) it might be worth re-consulting with the ML group to look for alternative algorithms.

## Model Training
Someone will need to read through documents and actually label locations correctly. We have some of this information already, but we will need more. One potential might be to crowd-source it within the AZGS office.

## Prediction
[Skipping this description]

## Requirements
Our scope of work states that we will achieve 80% accuracy, which makes it unclear whether we mean precision or recall. In this context, we want to focus on precison.

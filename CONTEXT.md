# Glossary

Domain terms for this SPTAG fork and its Aerospike-backed posting storage. Definitions only — no build steps, file paths, or implementation detail.

## AEROSPIKEIO

SPANN storage mode where durable posting lists live in Aerospike. The in-RAM head graph and graph traversal stay in SPTAG.

## ComputeDistance

SPTAG routine that scores tail vectors inside posting blobs after postings are fetched. Baseline query path runs this in the client; server-side distance offload is a separate target.

## Extra searcher

`IExtraSearcher` implementation that owns posting I/O and related metadata (for example version maps). With `Storage=AEROSPIKEIO`, postings are read and written through the Aerospike KV backend. Does not own the ANN graph.

## Head graph

In-RAM approximate-nearest-neighbor structures (BKT or KDT plus relative neighborhood graph) used for coarse search at query time. Loaded from the index folder (for example `graph.bin`, BK-tree, head vectors).

## Head ID

Numeric identifier for one head vector. In Aerospike mode, the Aerospike record key for that head’s posting list.

## Neighborhood graph (RNG)

SPTAG in-memory adjacency structure (`RelativeNeighborhoodGraph`, persisted as `graph.bin`). Used for greedy graph traversal during search. Not stored in Aerospike.

## Posting list

Blob keyed by head ID. Packed tail vectors and metadata for vectors assigned to that head cluster.

## SPANN

Two-tier index: head graph search in RAM, then fetch of posting lists from SSD, RocksDB, file I/O, SPDK, or Aerospike depending on `Storage`. Query flow: head search → fetch postings → distance on tail vectors → merge top-K.

## Tail vector

One embedding inside a posting list. The unit distance is computed against during the posting scan phase of a query.

## VectorIndex

In-process SPTAG search object after `LoadIndex`. Holds query-time head index state. Not the Aerospike server and not shared across processes unless each process loads its own copy.

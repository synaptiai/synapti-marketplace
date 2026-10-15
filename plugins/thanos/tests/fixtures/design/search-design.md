# Product search: design

## Problem

Customers cannot find products by name. Support gets about 40 tickets a
week asking where an item is. The catalogue has 3,000 products and grows
by about 50 a month.

## Proposal

Add a search box to the shop header that returns matching products as the
customer types.

### Components

- **Search service**: a new microservice with its own deployment, owning
  the search index and exposing a REST and a GraphQL API.
- **Elasticsearch cluster**: three nodes, for relevance ranking and
  future faceted search, synonyms and multi-language stemming.
- **Indexing pipeline**: a Kafka topic carries product changes to an
  indexer worker, so that future sources (reviews, blog posts) can be
  indexed too.
- **Plugin system**: ranking strategies are loaded as plugins so that
  marketing can add boosting rules later.
- **Search box**: a React component with debounced type-ahead.

### Rollout

Ship behind a feature flag to 10% of customers, then everyone.

## Open questions

- Which ranking plugins marketing will want.
- Whether to add voice search next year.

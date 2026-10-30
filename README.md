# Olist Retail & Customer Analytics (SQL Server)

An end-to-end SQL analytics project on the Olist Brazilian e-commerce dataset: database design, data loading, cleaning, business analysis, performance tuning, and a reusable reporting layer (views and a stored procedure) ready for a Power BI dashboard.

**Tech:** SQL Server 2025 Express, T-SQL, SSMS | **Dataset:** [Olist Brazilian E-Commerce (Kaggle)](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) | **Database:** `OlistRetailDB`, schema `ctr`
---

## Database Schema

The database schema illustrates the relationships between tables used in the Olist SQL Analytics project.

![schema_diagram](schema_diagram.png)

## 1. Problem statement

Olist is an online marketplace where many independent sellers sell to customers across Brazil. A business team running a marketplace like this needs clear answers to five questions:

1. **Revenue:** How much do we earn, and which products drive it?
2. **Growth:** Is revenue growing month over month, or has it stalled?
3. **Customers:** Who are our customers, how valuable are they, and do they come back?
4. **Delivery:** Where are we failing to deliver on time?
5. **Sellers:** Which sellers carry each state, and how concentrated is revenue?

This project answers all five using SQL, and packages the logic as views and a stored procedure so a dashboard can reuse it.

## 2. Dataset overview

Real (anonymised) marketplace orders from Olist, with real activity from about **Sep 2016 to Aug 2018**: roughly 99k orders, 112k line items and 3k sellers, loaded into 9 tables plus one audit table.

| Table | Rows | Key / note |
|---|---|---|
| customers | 99,441 | PK `customer_id`. `customer_unique_id` is the real person (not unique by design) |
| orders | 99,441 | PK `order_id`, FK to customers |
| order_items | 112,650 | Composite PK `(order_id, order_item_id)`. Bridge table: orders to products and sellers. Quantity = row count |
| order_payments | 103,886 | Composite PK `(order_id, payment_sequential)` |
| order_reviews | 99,224 | Composite PK `(review_id, order_id)` |
| products | 32,951 | PK `product_id` |
| sellers | 3,095 | PK `seller_id` |
| geolocation | 1,000,163 | No PK (one zip maps to many coordinates) |
| product_category_name_translation | 71 | Portuguese to English category names |
| data_quality_log | 14 | Audit table for anomalies I flagged but did not alter |

**Relationships:** customers 1-to-many orders; orders 1-to-many order_items, order_payments and order_reviews; order_items many-to-one products and many-to-one sellers.

**One thing to know before reading the analysis:** every order gets a new `customer_id`, so one person who orders three times has three `customer_id`s but one `customer_unique_id`. All customer analysis (RFM, retention) therefore groups by `customer_unique_id`.

**Revenue definition used throughout:** `SUM(order_items.price)`, which excludes freight, counting only `delivered` (confirmed) or `delivered + shipped` (including in-transit) orders. Canceled and unavailable orders are never revenue.

## 3. Key findings

**Revenue.** 13.22M from delivered orders (96,478 orders); 13.37M including in-transit orders. The top product was a health & beauty item with 63,885 revenue from 195 units. None of the top 10 products were uncategorised.

**Growth.** Month-over-month revenue grew strongly through 2017 (Feb 2017 +108%), reaching about 995k in Nov 2017 (+52%), dipped in Dec 2017 (-26%), then plateaued around 850k-990k through 2018. The +1,047,579% figure that appears for Jan 2017 is an artefact of a near-zero base month (Dec 2016 revenue was 10.90), so the analysis reports Feb 2017 to Aug 2018.

**Customers (RFM).** 94,398 customers split into six segments:

| Segment | Customers |
|---|---|
| New / Promising | 36,531 |
| Lost | 22,822 |
| At-Risk | 20,905 |
| Needs Attention | 11,279 |
| Loyal | 1,634 |
| Champions | 1,227 |

*At-Risk* customers hold about **42% of revenue** (average spend 268), the biggest recoverable opportunity. Champions and Loyal together are only about 3% of customers.

**Retention.** **96.97% of customers buy only once** (94.46% of revenue, average 138.00). The 3.03% who return are worth more (average 258.85) because they order more often, not because their orders are bigger. Among customers who do return, the average time to a second order is 80.6 days but the median is only 28 days; about 68% return within 90 days. (This measures only customers who came back.)

**Delivery.** Of 96,470 delivered orders, **8.11% arrived late**, by 8.87 days on average when late; average delivery takes 12.50 days. Worst states by late rate (states with 100+ orders): AL 23.93%, MA 19.67%, PI 15.97%, CE 15.32%, SE 15.22%. By volume, SP (2,387) and RJ (1,664, 13.47%) have the most late orders. Rate and volume tell different stories, so both are shown.

**Sellers.** 2,977 of 3,095 sellers were active. Revenue is highly concentrated: in Bahia, the top seller has 352 orders and 220,199 revenue versus 17,522 for the second.

RFM Results

![RFM Results](03_rfm_segments.png)

Revenue Analysis Monthly

![MOM](07_monthly_growth.png)

## 4. What I built

| Layer | Objects |
|---|---|
| Reporting views | `vw_customer_rfm_segments`, `vw_customer_retention`, `vw_days_to_second_order`, `vw_delivery_sla_by_state`, `vw_seller_ranking`, `vw_monthly_revenue_growth` |
| Stored procedure | `usp_customer_rfm_segments` (RFM with a temp table, faster than the view) |
| Integrity | 3 trusted foreign keys on `order_items`; audit table `data_quality_log` |

Views return facts (all states, all sellers, all months). Cut-offs such as "100+ orders" or "top 3 per state" are applied by the dashboard, so nothing is hidden.

## 5. SQL techniques used

CTEs and multi-step CTE pipelines; window functions (`LAG`, `NTILE`, `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `LEAD`, windowed `SUM`, `PERCENTILE_CONT`); conditional aggregation (`SUM(CASE ...)`); `COUNT(DISTINCT)`; self-joins; `TRY_CONVERT` and `CAST`; staging-table loading; temp tables and stored procedures; foreign keys and constraint trust; execution-plan reading, `SET STATISTICS IO/TIME`, index rebuilds and index experiments.

## 6. Challenges and how I solved them

1. **Silent column misalignment in `orders`.** `BULK INSERT` maps by position, and my table's column order differed from the CSV, so every column after `order_id` loaded into the wrong place with no error. I found it by inspecting a row. I fixed it without truncating (child foreign keys blocked that) by loading a clean staging table and running `UPDATE ... JOIN` on the key, then redid and re-logged every earlier orders check, because they had been run on wrong data.
2. **Quoted CSV values** (payments, reviews) broke `BULK INSERT` and `FORMAT='CSV'` (Msg 7301). I used the Import Flat File wizard into staging, then `INSERT ... SELECT` with explicit casts.
3. **Day-first dates.** `orders` dates (dd-MM-yyyy) failed as DATETIME. The same format appeared in `order_items.shipping_limit_date`, where the default parse fails on 70,099 of 112,650 rows and would silently swap day and month on the rest. I converted with an explicit style (105), verified zero failures, and logged 4 source rows dated in 2020.
4. **`ISDATE()` returned 0 for every row** because it rejects 7-digit fractional seconds. I validated with `TRY_CONVERT` instead.
5. **Duplicate `review_id`** (25 ids shared by two orders). Deleting would lose real data, so the key became `(review_id, order_id)`.
6. **`customer_unique_id` not unique.** I dropped a UNIQUE constraint after confirming it was legitimate behaviour (2,997 repeat customers, worst case 17 orders), and documented it with an extended property.
7. **Data I refused to fake.** 8 `delivered` orders have no delivery date. I logged them and left NULL instead of inserting dummy dates that would poison delay averages.
8. **Foreign key length mismatch (Msg 1753).** `order_items.product_id` and `seller_id` had been widened to `varchar(100)` earlier; keys must match the parent length, so I narrowed them to `varchar(50)` after confirming the longest ID was 32 characters.

## 7. Performance tuning

Method: `SET STATISTICS IO, TIME ON`, actual execution plan, **one change at a time**, three runs each, comparing logical reads **and** CPU/elapsed time.

| Query | Finding | Result |
|---|---|---|
| RFM view | Two `NTILE` calls created two table spools: about 98% of 398k logical reads. Plan was all row mode (Express edition, single core) | Replacing `NTILE` with `ROW_NUMBER` arithmetic cut reads about 97%, but **time did not change**: reads were not the real cost |
| RFM view | The join and `COUNT(DISTINCT)` ran twice because a CTE was referenced twice | Storing the result once in a temp table inside a stored procedure cut CPU from about 1.9-2.0 s to about 1.3-1.7 s, and elapsed from about 2.6 s to about 2.0-2.3 s |
| `orders` table | 61% full pages and 98.8% fragmentation after a large UPDATE | `REBUILD`: 11,122 to 2,992 logical reads (-73%) |
| `order_items` | Table grew after adding a column | `REBUILD`: 4,549 to 1,992 reads (-56%) |
| Index `(order_status, order_purchase_timestamp)` | Missing-index hint | Kept: small read saving, no reliable time gain |
| SLA missing-index hint (impact 15.3) | Tested | Reads -15%, no CPU gain, overlaps an existing index, **dropped** |
| Seller ranking, SLA by state | Already about 350 ms, one pass per table | Measured, nothing worth changing |

**Lesson:** the biggest number in the Messages tab (spool reads) was not the real cost. Removing duplicated work, not chasing reads, produced the real gain. I also report indexes that did not help.

**Correctness check of the rewrite:** the `ROW_NUMBER` scoring matches `NTILE` bucket sizes to within one row per boundary and moves 44 customers (0.05%) between segments because of tie ordering, with all findings unchanged.

![Tuning](<11_Tuning Summary.png>)

## 8. Repository structure

```
olist-sql-analytics/
├── README.md
├── .gitignore
├── sql/
│   ├── 01_create_tables.sql
│   ├── 02_load_data.sql
│   ├── 03_data_cleaning.sql
│   ├── 04_revenue_top_products_mom.sql
│   ├── 05_rfm_segmentation.sql
│   ├── 06_retention.sql
│   ├── 07_delivery_sla.sql
│   ├── 08_seller_ranking.sql
│   ├── 09_performance_tuning.sql
│   ├── 10_foreign_keys_and_fixes.sql
│   ├── 11_views.sql
│   ├── 12_usp_customer_rfm_segments.sql
│   └── 12_usp_customer_rfm_segments_test.sql
└── docs/
    ├── schema_diagram.pdf
    └── screenshots/

```

Files 02 and 03 document the load and cleaning as they were done; they are not a one-click rebuild.
If required .bak file, please contact me via linkedin (Link pasted below)


## 9. Limitations

- The dataset is a 2016-2018 snapshot; no forward-looking claims are made.
- Retention time-to-second-order measures only customers who returned.
- States with fewer than 100 delivered orders (RR, AP, AC) are excluded from state comparisons as too noisy.
- Revenue excludes freight by definition.
- SQL Server Express limits parallelism, so absolute timings will differ on other editions.

## 10. Next steps

Migrate the database to Azure SQL Database and build a Power BI dashboard on the views (Import mode, scheduled refresh). Then a second project on banking transaction analytics.

## 11. About

Built by **Sarvesh Sabnis**, SQL Developer with experience in SQL Server, PostgreSQL, stored procedures, ETL, and query optimization, building toward Data Engineering.
[GitHub](https://github.com/The-sabnis)
[Linkedin](https://www.linkedin.com/in/sarvesh-sabnis-002392242/)

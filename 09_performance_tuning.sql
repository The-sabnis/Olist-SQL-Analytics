/* =====================================================================
   09_performance_tuning.sql
   Project : Olist Retail Analytics (OlistRetailDB, schema ctr)
   Purpose : Baselines, fixes and index experiments for the RFM view,
             seller ranking and delivery SLA queries.
   Method  : SET STATISTICS IO, TIME ON; one change at a time;
             3 runs per test; compare logical reads AND CPU/elapsed.
   ===================================================================== */
USE OlistRetailDB;
GO
SET STATISTICS IO, TIME ON;
GO

/* ---------------------------------------------------------------------
   1. RFM VIEW: BASELINE (no secondary indexes)
   --------------------------------------------------------------------- */
SELECT segment, COUNT(*) AS customers
FROM ctr.vw_customer_rfm_segments
GROUP BY segment;
/* Result (cold and warm identical):
   Worktable reads 398,421 | orders 11,122 | order_items 2,269 | customers 1,272
   CPU ~2,050 ms, elapsed ~2,200 ms
   Plan: all operators Row mode (Express edition, single core).
   Two Table Spools (from the two NTILE calls) = ~396k of the Worktable reads. */

/* ---------------------------------------------------------------------
   2. REBUILD orders (bloat left by the earlier column-fix UPDATE)
   --------------------------------------------------------------------- */
SELECT index_level, page_count, avg_fragmentation_in_percent, avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('ctr.orders'), NULL, NULL, 'DETAILED')
WHERE index_level = 0;
/* Before: 5,513 pages, 98.8% fragmented, pages 61.4% full */

ALTER INDEX ALL ON ctr.orders REBUILD;
/* Result: orders reads 11,122 -> 2,992 (-73%). CPU/elapsed essentially unchanged. */

/* ---------------------------------------------------------------------
   3. INDEX EXPERIMENT 1 (kept)
   --------------------------------------------------------------------- */
CREATE NONCLUSTERED INDEX ix_orders_status_purchase
ON ctr.orders (order_status, order_purchase_timestamp)
INCLUDE (customer_id);
GO
/* Result: orders reads 2,992 -> 2,633. Worktable unchanged (398,421).
   CPU 1,672 ms on one run but 2,048 ms in the plan capture, so no reliable
   time gain. Kept: small read saving, negligible write cost on this
   read-heavy database. */

/* ---------------------------------------------------------------------
   4. REWRITE: NTILE(5) -> ROW_NUMBER() + arithmetic (no spool)
   --------------------------------------------------------------------- */
/* Core idea:  score = 5 * (rn - 1) / n + 1
   rn = ROW_NUMBER() OVER (ORDER BY ..., customer_unique_id)  (tiebreaker => repeatable)
   n  = total customers, computed once in a one-row COUNT(*) subquery. */
/* Result (6-row GROUP BY version):
   Worktable reads 0 | total reads ~11,200 (base tables read twice: CTE used twice)
   CPU 1,750-1,843 ms, elapsed 1,767-1,879 ms  -> reads down ~97%, time unchanged. */

/* Correctness check vs old view:
   r_score bucket sizes: old 18,880/18,880/18,880/18,879/18,879
                         new 18,880/18,880/18,879/18,880/18,879
   Segment counts differ for 44 customers (0.05%): At-Risk +39, Champions -2,
   Loyal +2, Needs Attention -42, New/Promising +3, Lost 0 (net 0).
   Revenue per segment sums to 13,372,225.55. Business findings unchanged. */

/* ---------------------------------------------------------------------
   5. TEMP TABLE: compute the join + COUNT(DISTINCT) once
   --------------------------------------------------------------------- */
/* See 12_usp_customer_rfm_segments.sql (SELECT ... INTO #rfm, then score from #rfm).
   Base tables now read once: order_items 2,269 | orders 2,633 | customers 1,272
   Step 1 ~830 ms CPU, step 2 ~480-580 ms CPU. */

/* Like-for-like, both returning 94,398 rows:
   View      (SELECT *)                 CPU 1,859-2,016 ms | elapsed 2,593-2,603 ms | Worktable 483,368
   Procedure (EXEC)                     CPU 1,297-1,469 ms | elapsed 1,943-2,008 ms | Worktable 0
   After later order_items rebuild (re-measured): procedure CPU 1,500-1,657 ms,
   elapsed 2,260-2,521 ms (some run-to-run noise on this machine). Still below the view.
   Lesson: the biggest number in the Messages tab (spool reads) was not the real
   cost; not computing the same join twice was the real win. */

/* ---------------------------------------------------------------------
   6. SELLER RANKING: BASELINE AND order_items REBUILD
   --------------------------------------------------------------------- */
/* Baseline: sellers 29 | orders 1,496 | order_items 4,549 | no spools
   CPU 344-375 ms, elapsed 338-417 ms. No missing-index hint. */
/* order_items had grown after adding shipping_limit_dt (see file 10). */
ALTER INDEX ALL ON ctr.order_items REBUILD;
/* Result: order_items reads 4,549 -> 1,992 (-56%). CPU ~360 ms, unchanged.
   No index on order_items(seller_id): query reads every row, so no benefit expected. */

/* ---------------------------------------------------------------------
   7. DELIVERY SLA BY STATE: BASELINE AND INDEX EXPERIMENT 2 (dropped)
   --------------------------------------------------------------------- */
/* Baseline: customers 1,272 | orders 1,496 | one scan each | no spools
   CPU 328-406 ms, elapsed 340-399 ms. */
CREATE NONCLUSTERED INDEX ix_orders_status_delivered
ON ctr.orders (order_status, order_delivered_customer_date)
INCLUDE (order_purchase_timestamp, order_estimated_delivery_date, customer_id);
GO
/* Missing-index hint impact was 15.3. Result: orders reads 1,496 -> 1,267 (-15%),
   CPU 359 / 360 / 625 ms (no improvement), elapsed higher. Overlaps with
   ix_orders_status_purchase. Decision: dropped. */
DROP INDEX ix_orders_status_delivered ON ctr.orders;
GO

SET STATISTICS IO, TIME OFF;
GO

/* ---------------------------------------------------------------------
   SUMMARY
   - Logical reads are not time: cutting reads ~97% (spools) or 73% (rebuild)
     did not change CPU; removing duplicated work did.
   - Indexes tested: 1 kept (small read gain), 1 dropped (no CPU gain).
   - Seller ranking and SLA already ~350 ms with one pass per table.
   --------------------------------------------------------------------- */
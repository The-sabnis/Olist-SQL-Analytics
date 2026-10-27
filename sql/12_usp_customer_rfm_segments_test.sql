CREATE TABLE #check (
    customer_unique_id varchar(50),
    frequency int,
    monetary decimal(12,2),
    recency int,
    r_score int,
    f_score int,
    m_score int,
    segment varchar(20)
);

INSERT INTO #check
EXEC ctr.usp_customer_rfm_segments;

SELECT COUNT(*) AS total_rows FROM #check;      -- expect 94,398

SELECT segment, COUNT(*) AS customers, SUM(monetary) AS revenue
FROM #check
GROUP BY segment
ORDER BY segment;                               -- Champions expect 1,225

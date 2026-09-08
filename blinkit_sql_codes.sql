/* ============================================================================
BLINKIT QUICK-COMMERCE SQL ANALYTICS PROJECT
Database: MySQL
============================================================================ */


/* ============================================================================
   PART 1 - DATABASE & RAW TABLE SETUP
   ============================================================================ */

USE blinkit_analytics;

CREATE TABLE blinkit_raw (
    product_id          INT,
    product_name        VARCHAR(255),
    category            VARCHAR(100),
    brand               VARCHAR(100),
    price               DECIMAL(10,2),
    discount_pct        DECIMAL(5,2),
    final_price         DECIMAL(10,2),
    rating              DECIMAL(3,2),
    num_reviews         INT,
    delivery_time_min   INT,
    city                VARCHAR(100),
    seller              VARCHAR(100),
    stock               INT,
    sold_quantity       INT,
    profit_margin_pct   DECIMAL(5,2),
    is_organic          BOOLEAN,        -- later altered to VARCHAR(10), see Part 2
    packaging_type      VARCHAR(100),
    weight_g            DECIMAL(10,2),
    shelf_life_days     INT,
    reorder_level       INT,
    demand_index        DECIMAL(5,2),
    date_added          DATE,
    expiry_date         DATE,
    offer_type          VARCHAR(100),
    delivery_status     VARCHAR(50)
);

-- Sanity checks after table creation
DESCRIBE blinkit_raw;

SELECT COUNT(*) AS total_rows
FROM blinkit_raw;   -- expected: 0 (table is empty before CSV import)



-- /* ============================================
--  part 2 - Load CSV Data into Table
-- ============================================*/

USE blinkit_analytics;
SET GLOBAL local_infile = 1;
LOAD DATA LOCAL INFILE 'C:/Users/Lenovo/Downloads/blinkit_dataset.csv'
INTO TABLE blinkit_raw
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


SELECT COUNT(*) AS total_rows
FROM blinkit_raw;


/* ============================================================================
   PART 3 - FINDING & REMOVING DUPLICATE ROWS

   Question: Is the row count we got after import (19,231) correct, or did the
   CSV get imported more than once by accident?
   ============================================================================ */

-- 3.1 Spot-check first and last rows
SELECT * FROM blinkit_raw LIMIT 5;

SELECT * FROM blinkit_raw
ORDER BY product_id DESC
LIMIT 5;

-- 3.2 Compare total rows vs. distinct product_id count
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_id)  AS unique_products
FROM blinkit_raw;
-- Result: total_rows = 19,231 | unique_products = 13,000

-- 3.3 How many times does each product_id repeat?
SELECT
    duplicate_count,
    COUNT(*) AS number_of_products
FROM (
    SELECT product_id, COUNT(*) AS duplicate_count
    FROM blinkit_raw
    GROUP BY product_id
) AS x
GROUP BY duplicate_count
ORDER BY duplicate_count;

-- Result:
--   # duplicate_count |	number_of_products
--          1		   |		6954
--          2	       |		5861
--          3		   |		185
-- Check: 6954 + (5861*2) + (185*3) = 19,231 rows (matches total_rows above)

-- 3.4 Inspect the repeated rows to confirm they are exact duplicates
SELECT *
FROM blinkit_raw
WHERE product_id IN (
    SELECT product_id
    FROM blinkit_raw
    GROUP BY product_id
    HAVING COUNT(*) > 1
)
ORDER BY product_id
LIMIT 20;
-- Confirmed: every column is identical across the repeated rows for a given
-- product_id -> these are accidental duplicate imports, not distinct records.

-- 3.5 Build a clean table with exact duplicates removed
CREATE TABLE blinkit_clean AS
SELECT DISTINCT *
FROM blinkit_raw;

SELECT COUNT(*) AS clean_rows
FROM blinkit_clean;
-- Result: 13,000

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_id) AS unique_products
FROM blinkit_clean;
-- Result: 13,000 / 13,000 -> one row per product, blinkit_raw is left untouched


/* ============================================================================
   PART 4 - DATA QUALITY & VALIDATION CHECKS (run on blinkit_clean)
   ============================================================================ */

-- 4.1 NULL check on key columns
SELECT
    SUM(product_id   IS NULL) AS product_id_nulls,
    SUM(product_name IS NULL) AS product_name_nulls,
    SUM(category     IS NULL) AS category_nulls,
    SUM(brand        IS NULL) AS brand_nulls,
    SUM(price        IS NULL) AS price_nulls,
    SUM(discount_pct IS NULL) AS discount_nulls,
    SUM(final_price  IS NULL) AS final_price_nulls,
    SUM(rating       IS NULL) AS rating_nulls,
    SUM(stock        IS NULL) AS stock_nulls,
    SUM(city         IS NULL) AS city_nulls,
    SUM(is_organic   IS NULL) AS organic_nulls
FROM blinkit_clean;
-- Result: 0 NULLs across every column checked

-- 4.2 Check the distinct values stored in is_organic
SELECT
    is_organic,
    COUNT(*) AS count
FROM blinkit_clean
GROUP BY is_organic;
-- Result: True -> 3,168 | False -> 9,832 (no stray/blank values)

-- 4.3 Range checks on core numeric/price columns
SELECT
    MIN(price)        AS min_price,        MAX(price)        AS max_price,
    MIN(discount_pct) AS min_discount,     MAX(discount_pct) AS max_discount,
    MIN(final_price)  AS min_final_price,  MAX(final_price)  AS max_final_price,
    MIN(rating)       AS min_rating,       MAX(rating)       AS max_rating
FROM blinkit_clean;
-- Result: price 10.18-999.93 | discount 0-30% | final_price 8.14-998.92 | rating 2.5-5.0

-- 4.4 Range checks on operational columns
SELECT
    MIN(stock)              AS min_stock,          MAX(stock)              AS max_stock,
    MIN(sold_quantity)      AS min_sold_quantity,  MAX(sold_quantity)      AS max_sold_quantity,
    MIN(delivery_time_min)  AS min_delivery_time,  MAX(delivery_time_min)  AS max_delivery_time,
    MIN(profit_margin_pct)  AS min_profit_margin,  MAX(profit_margin_pct) AS max_profit_margin,
    MIN(shelf_life_days)    AS min_shelf_life,     MAX(shelf_life_days)   AS max_shelf_life,
    MIN(reorder_level)      AS min_reorder_level,  MAX(reorder_level)     AS max_reorder_level,
    MIN(demand_index)       AS min_demand_index,   MAX(demand_index)      AS max_demand_index
FROM blinkit_clean;
-- Result: stock 52-169 | sold_qty 0-720 | delivery 10-56 min | margin 5-40%
--         shelf_life 2-1825 days | reorder_level 10-33 | demand_index 0-100

-- 4.5 Date consistency checks
SELECT
    MIN(date_added)  AS earliest_added,  MAX(date_added)  AS latest_added,
    MIN(expiry_date) AS earliest_expiry, MAX(expiry_date) AS latest_expiry
FROM blinkit_clean;
-- Result: added 2023-10-28 to 2025-10-27 | expiry 2023-10-30 to 2030-10-19

-- 4.6 Business-rule checks: invalid dates & price mismatches
SELECT
    SUM(expiry_date < date_added) AS invalid_dates,
    SUM(ROUND(price * (1 - discount_pct/100), 2) <> final_price) AS price_mismatches
FROM blinkit_clean;

-- Result: invalid_dates = 0 | price_mismatches = 0 -> data passes all core checks


/* ============================================================================
   PART 5 — BUILD THE FINAL ANALYSIS TABLE

   Converts is_organic from text ("True"/"False") to a numeric flag (1/0)
   so it can be used directly in aggregations, filters, and any BI tool.
   ============================================================================ */

CREATE TABLE blinkit_analysis AS
SELECT
    product_id,
    product_name,
    category,
    brand,
    price,
    discount_pct,
    final_price,
    rating,
    num_reviews,
    delivery_time_min,
    city,
    seller,
    stock,
    sold_quantity,
    profit_margin_pct,
    CASE
        WHEN is_organic = 'True'  THEN 1
        WHEN is_organic = 'False' THEN 0
    END AS is_organic,
    packaging_type,
    weight_g,
    shelf_life_days,
    reorder_level,
    demand_index,
    date_added,
    expiry_date,
    offer_type,
    delivery_status
FROM blinkit_clean;

-- Verification
SELECT COUNT(*) AS total_rows FROM blinkit_analysis;                 -- expected: 13,000

SELECT is_organic, COUNT(*) AS count
FROM blinkit_analysis
GROUP BY is_organic;                                                  -- expected: 0 -> 9,832 | 1 -> 3,168

DESCRIBE blinkit_analysis;


/* ============================================================================
   PART 6 — BUSINESS ANALYSIS
   All queries below run against blinkit_analysis, the analysis-ready table.
   ============================================================================ */

-- ---------------------------------------------------------------------------
-- Analysis 1: What does the overall business look like?
-- ---------------------------------------------------------------------------
SELECT
    COUNT(*)                                             AS total_products,
    SUM(sold_quantity)                                   AS total_units_sold,
    ROUND(SUM(sold_quantity * final_price), 2)           AS total_revenue,
    ROUND(AVG(final_price), 2)                           AS avg_selling_price,
    ROUND(AVG(discount_pct), 2)                          AS avg_discount,
    ROUND(AVG(rating), 2)                                AS avg_rating,
    ROUND(SUM(sold_quantity * final_price * profit_margin_pct / 100), 2) AS estimated_profit
FROM blinkit_analysis;

-- ---------------------------------------------------------------------------
-- Analysis 2: Which product categories generate the most revenue and profit?
-- ---------------------------------------------------------------------------
SELECT
    category,
    COUNT(*)                                            AS total_products,
    SUM(sold_quantity)                                   AS units_sold,
    ROUND(SUM(sold_quantity * final_price), 2)           AS revenue,
    ROUND(SUM(sold_quantity * final_price * profit_margin_pct / 100), 2) AS estimated_profit,
    ROUND(AVG(rating), 2)                                AS avg_rating
FROM blinkit_analysis
GROUP BY category
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- Analysis 3: Which brands perform best (Top 15 by revenue)?
-- ---------------------------------------------------------------------------
SELECT
    brand,
    COUNT(*)                                            AS total_products,
    SUM(sold_quantity)                                   AS units_sold,
    ROUND(SUM(sold_quantity * final_price), 2)           AS revenue,
    ROUND(SUM(sold_quantity * final_price * profit_margin_pct / 100), 2) AS estimated_profit,
    ROUND(AVG(rating), 2)                                AS avg_rating
FROM blinkit_analysis
GROUP BY brand
ORDER BY revenue DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Analysis 4: Does a higher discount lead to higher sales?
-- ---------------------------------------------------------------------------
SELECT
    CASE
        WHEN discount_pct = 0    THEN 'No Discount'
        WHEN discount_pct <= 5   THEN '1-5%'
        WHEN discount_pct <= 10  THEN '6-10%'
        WHEN discount_pct <= 20  THEN '11-20%'
        ELSE '21-30%'
    END AS discount_band,
    COUNT(*)                                   AS total_products,
    SUM(sold_quantity)                         AS units_sold,
    ROUND(SUM(sold_quantity * final_price), 2) AS revenue,
    ROUND(AVG(sold_quantity), 2)               AS avg_units_sold_per_product
FROM blinkit_analysis
GROUP BY discount_band
ORDER BY
    CASE
        WHEN discount_band = 'No Discount' THEN 1
        WHEN discount_band = '1-5%'        THEN 2
        WHEN discount_band = '6-10%'       THEN 3
        WHEN discount_band = '11-20%'      THEN 4
        ELSE 5
    END;

-- ---------------------------------------------------------------------------
-- Analysis 5: Which cities have the highest demand / revenue?
-- ---------------------------------------------------------------------------
SELECT
    city,
    COUNT(*)                                            AS total_products,
    SUM(sold_quantity)                                   AS units_sold,
    ROUND(SUM(sold_quantity * final_price), 2)           AS revenue,
    ROUND(SUM(sold_quantity * final_price * profit_margin_pct / 100), 2) AS estimated_profit,
    ROUND(AVG(rating), 2)                                AS avg_rating
FROM blinkit_analysis
GROUP BY city
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- Analysis 6: Which products need restocking?
-- ---------------------------------------------------------------------------

-- 6a: How many products are at or below their reorder level right now?
SELECT
    COUNT(*) AS products_needing_restock
FROM blinkit_analysis
WHERE stock <= reorder_level;

-- 6b: Since none have crossed the threshold, find the products with the
--     smallest buffer between current stock and reorder level (early-warning list)
SELECT
    product_id,
    product_name,
    category,
    brand,
    city,
    stock,
    reorder_level,
    (stock - reorder_level) AS stock_buffer,
    sold_quantity,
    demand_index
FROM blinkit_analysis
ORDER BY stock_buffer ASC
LIMIT 20;

-- ---------------------------------------------------------------------------
-- Analysis 7: Does delivery time affect sales performance?
-- ---------------------------------------------------------------------------
SELECT
    CASE
        WHEN delivery_time_min <= 15 THEN '10-15 min'
        WHEN delivery_time_min <= 25 THEN '16-25 min'
        WHEN delivery_time_min <= 35 THEN '26-35 min'
        WHEN delivery_time_min <= 45 THEN '36-45 min'
        ELSE '46-56 min'
    END AS delivery_band,
    COUNT(*)                                   AS total_products,
    SUM(sold_quantity)                         AS units_sold,
    ROUND(SUM(sold_quantity * final_price), 2) AS revenue,
    ROUND(AVG(sold_quantity), 2)               AS avg_units_sold_per_product,
    ROUND(AVG(rating), 2)                      AS avg_rating
FROM blinkit_analysis
GROUP BY delivery_band
ORDER BY
    CASE
        WHEN delivery_band = '10-15 min' THEN 1
        WHEN delivery_band = '16-25 min' THEN 2
        WHEN delivery_band = '26-35 min' THEN 3
        WHEN delivery_band = '36-45 min' THEN 4
        ELSE 5
    END;

-- ---------------------------------------------------------------------------
-- Analysis 8: Which sellers perform best (Top 15 by revenue)?
-- ---------------------------------------------------------------------------
SELECT
    seller,
    COUNT(*)                                            AS total_products,
    SUM(sold_quantity)                                   AS units_sold,
    ROUND(SUM(sold_quantity * final_price), 2)           AS revenue,
    ROUND(SUM(sold_quantity * final_price * profit_margin_pct / 100), 2) AS estimated_profit,
    ROUND(AVG(rating), 2)                                AS avg_rating
FROM blinkit_analysis
GROUP BY seller
ORDER BY revenue DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Analysis 9: Organic vs. Non-Organic performance
-- ---------------------------------------------------------------------------
SELECT
    CASE WHEN is_organic = 1 THEN 'Organic' ELSE 'Non-Organic' END AS product_type,
    COUNT(*)                                            AS total_products,
    SUM(sold_quantity)                                   AS units_sold,
    ROUND(SUM(sold_quantity * final_price), 2)           AS revenue,
    ROUND(SUM(sold_quantity * final_price * profit_margin_pct / 100), 2) AS estimated_profit,
    ROUND(AVG(final_price), 2)                           AS avg_price,
    ROUND(AVG(rating), 2)                                AS avg_rating
FROM blinkit_analysis
GROUP BY is_organic
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- Analysis 10: Which are the Top 10 most profitable individual products?
-- ---------------------------------------------------------------------------
SELECT
    product_id,
    product_name,
    category,
    brand,
    city,
    sold_quantity,
    final_price,
    profit_margin_pct,
    ROUND(sold_quantity * final_price, 2)                          AS revenue,
    ROUND(sold_quantity * final_price * profit_margin_pct / 100, 2) AS estimated_profit
FROM blinkit_analysis
ORDER BY estimated_profit DESC
LIMIT 10;

/* ============================================================================
   END OF SCRIPT
   ============================================================================ */

/* ============================================================
   PROJECT: Retail Store Sales - Data Cleaning & EDA
   TOOL: SQL Server (T-SQL)
   AUTHOR: Yahia Farag
   ============================================================
   Dataset: 12,575 rows of retail transactions
   Columns: Transaction_ID, Customer_ID, Category, Item,
            Price_Per_Unit, Quantity, Total_Spent,
            Payment_Method, Location, Transaction_Date,
            Discount_Applied
   ============================================================ */


/* ------------------------------------------------------------
   STEP 1: INITIAL DATA PROFILING
   ------------------------------------------------------------ */

-- Total row count
SELECT COUNT(*) AS total_rows FROM retail_store_sales;

-- Missing value count per column (all in one row for quick overview)
SELECT
    SUM(CASE WHEN Item IS NULL THEN 1 ELSE 0 END) AS Missing_Item,
    SUM(CASE WHEN Price_Per_Unit IS NULL THEN 1 ELSE 0 END) AS Missing_Price,
    SUM(CASE WHEN Quantity IS NULL THEN 1 ELSE 0 END) AS Missing_Quantity,
    SUM(CASE WHEN Total_Spent IS NULL THEN 1 ELSE 0 END) AS Missing_Total,
    SUM(CASE WHEN Discount_Applied IS NULL THEN 1 ELSE 0 END) AS Missing_Discount
FROM retail_store_sales;

-- Structural check: confirm Transaction_ID (Primary Key) has no duplicates
SELECT Transaction_ID, COUNT(*) AS CountDuplicates
FROM retail_store_sales
GROUP BY Transaction_ID
HAVING COUNT(*) > 1;
-- Result: 0 rows -> Transaction_ID is safely unique


/* ------------------------------------------------------------
   STEP 2: VERIFY THE MATH RELATIONSHIP
   Total_Spent = Price_Per_Unit x Quantity
   This lets us recover missing values mathematically instead
   of deleting or guessing.
   ------------------------------------------------------------ */

SELECT Price_Per_Unit, Quantity, Total_Spent
FROM retail_store_sales
WHERE Price_Per_Unit IS NOT NULL
  AND Quantity IS NOT NULL
  AND Total_Spent IS NOT NULL
  AND Total_Spent <> (Quantity * Price_Per_Unit);
-- Result: 0 mismatches out of 11,362 complete rows -> relationship holds 100%


/* ------------------------------------------------------------
   STEP 3: RECOVER MISSING Price_Per_Unit
   ------------------------------------------------------------ */

-- Pre-check: preview the rows and the value that will be calculated
SELECT Total_Spent, Quantity, Price_Per_Unit,
       (Total_Spent / Quantity) AS NewPrice
FROM retail_store_sales
WHERE Price_Per_Unit IS NULL
  AND Total_Spent IS NOT NULL
  AND Quantity IS NOT NULL
  AND Quantity <> 0;

-- Pre-check count (expected: 609)
SELECT COUNT(*) AS CountRows
FROM retail_store_sales
WHERE Price_Per_Unit IS NULL
  AND Total_Spent IS NOT NULL
  AND Quantity IS NOT NULL
  AND Quantity <> 0;

-- UPDATE: recover Price_Per_Unit, protected against divide-by-zero
UPDATE retail_store_sales
SET Price_Per_Unit = Total_Spent / Quantity
WHERE Price_Per_Unit IS NULL
  AND Total_Spent IS NOT NULL
  AND Quantity IS NOT NULL
  AND Quantity <> 0;

-- Post-check (expected: 0 rows remaining)
SELECT COUNT(*) AS CountNulls
FROM retail_store_sales
WHERE Price_Per_Unit IS NULL;


/* ------------------------------------------------------------
   STEP 4: HANDLE MISSING Item
   No column can reliably indicate the exact product name,
   so missing values are filled with 'Unknown'.
   ------------------------------------------------------------ */

-- Pre-check count (expected: 1213)
SELECT COUNT(*) AS CountNulls
FROM retail_store_sales
WHERE Item IS NULL;

-- UPDATE
UPDATE retail_store_sales
SET Item = 'Unknown'
WHERE Item IS NULL;

-- Post-check (expected: 0)
SELECT COUNT(*) AS CountNulls
FROM retail_store_sales
WHERE Item IS NULL;


/* ------------------------------------------------------------
   STEP 5: HANDLE MISSING Discount_Applied (~33% missing)
   Root-cause testing showed missingness is NOT related to
   year or payment method (evenly distributed ~33% across all).
   Decision: keep the original column untouched, and add a new
   classification column instead of overwriting raw data.
   ------------------------------------------------------------ */

-- Test 1: missingness by year (result: evenly distributed ~33% each year)
SELECT YEAR(Transaction_Date) AS Year, COUNT(*) AS CountNulls
FROM retail_store_sales
WHERE Discount_Applied IS NULL
GROUP BY YEAR(Transaction_Date);

-- Test 2: missingness by payment method (result: evenly distributed ~33% each)
SELECT Payment_Method, COUNT(*) AS CountNulls
FROM retail_store_sales
WHERE Discount_Applied IS NULL
GROUP BY Payment_Method;

-- Add new classification column
ALTER TABLE retail_store_sales
ADD Discount_Status VARCHAR(20);

-- Populate it based on the original column
UPDATE retail_store_sales
SET Discount_Status =
    CASE
        WHEN Discount_Applied = 1 THEN 'Applied'
        WHEN Discount_Applied = 0 THEN 'Not Applied'
        WHEN Discount_Applied IS NULL THEN 'Not Recorded'
    END;

-- Verify distribution
SELECT Discount_Status, COUNT(*) AS CountRows
FROM retail_store_sales
GROUP BY Discount_Status;


/* ------------------------------------------------------------
   STEP 6: CONSISTENCY CHECKS ON TEXT COLUMNS
   ------------------------------------------------------------ */

-- Check for hidden duplicates in categorical values
SELECT DISTINCT Category FROM retail_store_sales;      -- expected 8
SELECT DISTINCT Payment_Method FROM retail_store_sales; -- expected 3
SELECT DISTINCT Location FROM retail_store_sales;       -- expected 2

-- Check for leading/trailing whitespace issues
SELECT LEN(Category) AS Name_Length
FROM retail_store_sales
WHERE LEN(Category) <> LEN(TRIM(Category));
-- Result: 0 rows -> no whitespace issues


/* ------------------------------------------------------------
   STEP 7: OUTLIER CHECKS ON NUMERIC COLUMNS
   ------------------------------------------------------------ */

SELECT MAX(Quantity), MIN(Quantity), ROUND(AVG(Quantity), 2)
FROM retail_store_sales;

SELECT MAX(Price_Per_Unit), MIN(Price_Per_Unit), ROUND(AVG(Price_Per_Unit), 2)
FROM retail_store_sales;
-- All values fall within a reasonable retail range -> no outliers found


/* ------------------------------------------------------------
   STEP 8: BUSINESS QUESTIONS / EDA
   ------------------------------------------------------------ */

-- Total revenue by category
SELECT Category, SUM(Total_Spent) AS TotalRevenue
FROM retail_store_sales
GROUP BY Category
ORDER BY TotalRevenue DESC;

-- Orders and revenue by payment method
SELECT Payment_Method, COUNT(*) AS CountOrders, SUM(Total_Spent) AS TotalRevenue
FROM retail_store_sales
GROUP BY Payment_Method
ORDER BY TotalRevenue DESC;

-- Average order value by location (online vs in-store)
SELECT Location, COUNT(*) AS CountOrders, ROUND(AVG(Total_Spent), 2) AS AvgRevenue
FROM retail_store_sales
GROUP BY Location
ORDER BY AvgRevenue DESC;

-- Monthly revenue (excluding incomplete year 2025 for fair comparison)
SELECT MONTH(Transaction_Date) AS Month, SUM(Total_Spent) AS TotalRevenue
FROM retail_store_sales
WHERE YEAR(Transaction_Date) <> 2025
GROUP BY MONTH(Transaction_Date)
ORDER BY TotalRevenue DESC;

-- Average order value: discount Applied vs Not Applied
SELECT Discount_Status, COUNT(*) AS CountOrders, ROUND(AVG(Total_Spent), 2) AS AvgRevenue
FROM retail_store_sales
WHERE Discount_Status IN ('Applied', 'Not Applied')
GROUP BY Discount_Status;

-- Top-selling item per category (Window Function + CTE)
WITH RankedItems AS (
    SELECT
        Category,
        Item,
        COUNT(*) AS CountOrders,
        ROW_NUMBER() OVER (PARTITION BY Category ORDER BY COUNT(*) DESC) AS RankNum
    FROM retail_store_sales
    WHERE Item <> 'Unknown'
    GROUP BY Category, Item
)
SELECT Category, Item, CountOrders
FROM RankedItems
WHERE RankNum = 1;

-- Categories with above-average revenue (Subquery)
SELECT Category, ROUND(AVG(Total_Spent), 2) AS AvgRevenue
FROM retail_store_sales
GROUP BY Category
HAVING AVG(Total_Spent) > (SELECT AVG(Total_Spent) FROM retail_store_sales);

-- Each category's share of total revenue (%)
SELECT
    Category,
    SUM(Total_Spent) AS CategoryRevenue,
    ROUND(SUM(Total_Spent) * 100.0 / (SELECT SUM(Total_Spent) FROM retail_store_sales), 2) AS PercentageOfTotal
FROM retail_store_sales
GROUP BY Category
ORDER BY PercentageOfTotal DESC;

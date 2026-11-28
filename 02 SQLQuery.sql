
-- ============================================================
-- IKEA GIFTING: CUSTOMER ANALYTICS & RFM SEGMENTATION
-- SQL SERVER DATA PREPARATION
-- ============================================================


-- STEP 1: CREATE DATABASE

IF DB_ID('EcommerceCustomerAnalytics') IS NULL
BEGIN
    CREATE DATABASE EcommerceCustomerAnalytics;
END;
GO

USE EcommerceCustomerAnalytics;
GO

-- STEP 2: VERIFY SOURCE DATASETS

SELECT COUNT(*) AS Rows_2009_10
FROM dbo.[Year 2009 - 2010];

SELECT COUNT(*) AS Rows_2010_11
FROM dbo.[Year 2010 - 2011];


-- STEP 3: COMBINE BOTH YEARLY DATASETS
-- Convert InvoiceDate and Price into appropriate data types.
SELECT
        Invoice,
        StockCode,
        Description,
        Quantity,

        COALESCE(
            TRY_CONVERT(DATETIME2, InvoiceDate, 120),
            TRY_CONVERT(DATETIME2, InvoiceDate, 105)
        ) AS InvoiceDate,

        TRY_CONVERT(DECIMAL(10,2), Price) AS Price,

        Customer_ID,
        Country,
        '2009 - 2010' AS SourceSheet

    INTO dbo.RetailCombined

    FROM dbo.[Year 2009 - 2010]

    UNION ALL

    SELECT
        Invoice,
        StockCode,
        Description,
        Quantity,

        COALESCE(
            TRY_CONVERT(DATETIME2, InvoiceDate, 120),
            TRY_CONVERT(DATETIME2, InvoiceDate, 105)
        ) AS InvoiceDate,

        TRY_CONVERT(DECIMAL(10,2), Price) AS Price,

        Customer_ID,
        Country,
        '2010 - 2011' AS SourceSheet

    FROM dbo.[Year 2010 - 2011];

-- STEP 4: VALIDATE COMBINED DATA

SELECT
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN InvoiceDate IS NULL THEN 1 ELSE 0 END)
        AS Failed_Dates,
    SUM(CASE WHEN Price IS NULL THEN 1 ELSE 0 END)
        AS Failed_Prices
FROM dbo.RetailCombined;


-- STEP 5: CHECK MISSING CUSTOMER IDs

SELECT
    COUNT(*) AS Missing_Customer_ID
FROM dbo.RetailCombined
WHERE Customer_ID IS NULL;


-- STEP 6: CHECK NON-POSITIVE QUANTITIES

SELECT
    COUNT(*) AS NonPositive_Quantity_Records
FROM dbo.RetailCombined
WHERE Quantity <= 0;


-- STEP 7: REMOVE EXACT DUPLICATES
-- Keep one copy of each identical transaction.

WITH DeduplicatedData AS
    (
        SELECT
            *,
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    Invoice,
                    StockCode,
                    Description,
                    Quantity,
                    InvoiceDate,
                    Price,
                    Customer_ID,
                    Country
                ORDER BY SourceSheet
            ) AS RowNum

        FROM dbo.RetailCombined
    )

    SELECT
        Invoice,
        StockCode,
        Description,
        Quantity,
        InvoiceDate,
        Price,
        Customer_ID,
        Country,
        SourceSheet

    INTO dbo.RetailCleaned

    FROM DeduplicatedData

    WHERE RowNum = 1;

-- STEP 8: VERIFY CLEANED DATASET

SELECT
    (SELECT COUNT(*)
     FROM dbo.RetailCombined) AS Original_Rows,

    (SELECT COUNT(*)
     FROM dbo.RetailCleaned) AS Cleaned_Rows,

    (SELECT COUNT(*)
     FROM dbo.RetailCombined)
    -
    (SELECT COUNT(*)
     FROM dbo.RetailCleaned) AS Removed_Duplicates;


-- STEP 9: CHECK MISSING VALUES IN CLEANED DATA

SELECT
    SUM(CASE WHEN Invoice IS NULL THEN 1 ELSE 0 END)
        AS Missing_Invoice,

    SUM(CASE WHEN StockCode IS NULL THEN 1 ELSE 0 END)
        AS Missing_StockCode,

    SUM(CASE WHEN InvoiceDate IS NULL THEN 1 ELSE 0 END)
        AS Missing_InvoiceDate,

    SUM(CASE WHEN Price IS NULL THEN 1 ELSE 0 END)
        AS Missing_Price,

    SUM(CASE
            WHEN Description IS NULL
              OR LTRIM(RTRIM(Description)) = ''
            THEN 1 ELSE 0
        END) AS Missing_Description,

    SUM(CASE WHEN Customer_ID IS NULL THEN 1 ELSE 0 END)
        AS Missing_CustomerID,

    SUM(CASE WHEN Country IS NULL THEN 1 ELSE 0 END)
        AS Missing_Country

FROM dbo.RetailCleaned;

-- STEP 10: INVESTIGATE INVOICE PATTERNS AND IDENTIFY CANCELLATIONS

--1 SELECT DISTINCT Invoice FROM dbo.RetailCleaned WHERE Invoice LIKE '%[A-BD-Z]%';
--2 SELECT COUNT(DISTINCT Invoice) AS Other_Alphabet_Invoices FROM dbo.RetailCleaned WHERE Invoice LIKE '%[A-BD-Z]%';
--3 SELECT * FROM dbo.RetailCleaned WHERE Invoice LIKE 'A%' ORDER BY Invoice, InvoiceDate;
 
-- FINDING:
-- Six A-prefixed invoices were inspected.
-- Their descriptions identify them as bad-debt adjustments,
-- not ordinary product purchases.
--
-- DECISION:
-- Retain these records in RetailCleaned as part of the
-- historical transaction data.
--
-- RFM HANDLING:
-- These records have NULL Customer_ID and are therefore
-- excluded by the Python RFM filter.
--
-- NOTE:
-- This finding applies only to the six inspected
-- A-prefixed invoices, not automatically to every A-prefix.

SELECT
    COUNT(*) AS Cancelled_Records,
    COUNT(DISTINCT Invoice) AS Cancelled_Invoices,
    SUM(Quantity * Price) AS Cancellation_Value

FROM dbo.RetailCleaned

WHERE Invoice LIKE 'C%';


-- STEP 11: CHECK TRANSACTION DATE RANGE

SELECT
    MIN(InvoiceDate) AS First_Invoice_Date,
    MAX(InvoiceDate) AS Last_Invoice_Date

FROM dbo.RetailCleaned;

-- STEP 12: EXPORT CLEANED DATASET FOR PYTHON ANALYSIS

SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    Customer_ID,
    Country,
    SourceSheet
FROM dbo.RetailCleaned;


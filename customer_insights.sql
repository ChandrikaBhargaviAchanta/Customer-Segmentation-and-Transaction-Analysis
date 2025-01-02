-- STEP1: DATA PREPARATION 
-- Schema Creation 
-- Create the Transactions table with the necessary fields
CREATE TABLE Transactions (
    TransactionID VARCHAR(20) PRIMARY KEY, -- Unique ID for each transaction
    CustomerID VARCHAR(20), -- Unique ID for each customer
    CustomerDOB DATE, -- Customer's date of birth
    CustGender ENUM('Male', 'Female', 'Other'), -- Gender of the customer
    CustLocation VARCHAR(50), -- Customer's location
    CustAccountBalance DECIMAL(15, 2), -- Account balance of the customer
    TransactionDate DATE, -- Date of the transaction
    TransactionTime TIME, -- Time of the transaction
    TransactionAmount DECIMAL(15, 2) -- Transaction amount in INR
);


-- DATA CLEANING (Performed in Microsoft Excel)
-- Insert cleaned data into the Transactions table from RawTransactions
INSERT INTO Transactions
SELECT
    TransactionID,
    CustomerID,
    STR_TO_DATE(CustomerDOB, '%d/%m/%Y'), -- Convert DOB to a proper date format
    CASE
        WHEN CustGender = 'M' THEN 'Male' -- Standardize gender values
        WHEN CustGender = 'F' THEN 'Female'
        ELSE NULL
    END AS CustGender,
    CustLocation,
    CustAccountBalance, -- Retain the original account balance for accurate analysis
    STR_TO_DATE(TransactionDate, '%d/%m/%Y') AS TransactionDate, -- Convert transaction date
    SEC_TO_TIME(TransactionTime) AS TransactionTime, -- Convert transaction time
    GREATEST(0, TransactionAmount) AS TransactionAmount -- Ensure transaction amount is non-negative
FROM RawTransactions
WHERE CustomerID IS NOT NULL; -- Exclude records without CustomerID



-- STEP2: DATA PROCESSING
-- Add a column for customer age
ALTER TABLE Transactions ADD COLUMN CustomerAge INT;
-- Update age based on date of birth
UPDATE Transactions
SET CustomerAge = TIMESTAMPDIFF(YEAR, CustomerDOB, CURDATE())
WHERE CustomerDOB IS NOT NULL; -- Ensure DOB is non-null


-- Categorize customers into age groups for segmentation
ALTER TABLE Transactions ADD COLUMN AgeGroup VARCHAR(20);
-- Update age group based on age
UPDATE Transactions
SET AgeGroup = CASE
    WHEN CustomerAge < 18 THEN 'Under 18'
    WHEN CustomerAge BETWEEN 18 AND 25 THEN '18-25'
    WHEN CustomerAge BETWEEN 26 AND 35 THEN '26-35'
    WHEN CustomerAge BETWEEN 36 AND 50 THEN '36-50'
    WHEN CustomerAge > 50 THEN '50+'
    ELSE 'Unknown'
END;


-- Add a column for the year of the transaction
ALTER TABLE Transactions ADD COLUMN TransactionYear INT;
-- Update the year field using the transaction date
UPDATE Transactions
SET TransactionYear = YEAR(TransactionDate)
WHERE TransactionDate IS NOT NULL;


-- Identify High-Risk Customers (Negative Balances): Tag customers with negative balances for further investigation
-- Add a column to flag high-risk customers
ALTER TABLE Transactions ADD COLUMN IsHighRisk BOOLEAN;
-- Update the flag for customers with negative account balances
UPDATE Transactions
SET IsHighRisk = CASE
    WHEN CustAccountBalance < 0 THEN TRUE
    ELSE FALSE
END;




-- STEP:3 EXPLORATORY DATA ANALYSIS 
-- Get the total number of transactions for each customer
SELECT CustomerID, COUNT(*) AS TotalTransactions
FROM Transactions
GROUP BY CustomerID
ORDER BY TotalTransactions DESC;


-- Calculate the average transaction amount by gender
SELECT CustGender, AVG(TransactionAmount) AS AvgTransactionAmount
FROM Transactions
WHERE CustGender IS NOT NULL -- Avoid null values
GROUP BY CustGender;


-- Analyzing transaction behavior by age (Transaction frequency across age groups)
SELECT
    AgeGroup,
    COUNT(*) AS TransactionsCount,
    AVG(TransactionAmount) AS AvgTransactionAmount
FROM Transactions
GROUP BY AgeGroup
ORDER BY TransactionsCount DESC;


-- Identifying the top 5 revenue generating locations
SELECT
    CustLocation,
    SUM(TransactionAmount) AS TotalRevenue
FROM Transactions
GROUP BY CustLocation
ORDER BY TotalRevenue DESC
LIMIT 5;


-- Revenue breakdown by gender and location
SELECT
    CustGender,
    CustLocation,
    SUM(TransactionAmount) AS TotalRevenue,
    COUNT(*) AS TransactionsCount
FROM Transactions
WHERE CustGender IS NOT NULL AND CustLocation IS NOT NULL
GROUP BY CustGender, CustLocation
ORDER BY TotalRevenue DESC;


-- Monthly Transaction Count and Revenue: Useful for trend analysis
SELECT
    YEAR(TransactionDate) AS TransactionYear,
    MONTH(TransactionDate) AS TransactionMonth,
    COUNT(*) AS MonthlyTransactionCount,
    SUM(TransactionAmount) AS MonthlyRevenue
FROM Transactions
WHERE TransactionDate IS NOT NULL -- Ensure valid dates
GROUP BY TransactionYear, TransactionMonth
ORDER BY TransactionYear, TransactionMonth;


-- Calculate repeated customers: Tracking customers who made more than one transaction
SELECT
    CustomerID,
    COUNT(*) AS TransactionCount,
    CASE
        WHEN COUNT(*) > 1 THEN 'Repeat Customer'
        ELSE 'One-Time Customer'
    END AS CustomerType
FROM Transactions
GROUP BY CustomerID;


-- Peak Transaction Hours: Identify times of day with the highest activity
SELECT
    HOUR(TransactionTime) AS TransactionHour,
    COUNT(*) AS TransactionsCount,
    SUM(TransactionAmount) AS TotalRevenue
FROM Transactions
GROUP BY TransactionHour
ORDER BY TransactionsCount DESC;




-- STEP4: KEY METRICS EVALUATION
-- Revenue per Customer 
SELECT
    CustomerID,
    SUM(TransactionAmount) AS TotalRevenuePerCustomer,
    AVG(TransactionAmount) AS AvgTransactionPerCustomer
FROM Transactions
GROUP BY CustomerID
ORDER BY TotalRevenuePerCustomer DESC;


-- Identify the Top 10 high spenders  
SELECT
    CustomerID,
    SUM(TransactionAmount) AS TotalSpend
FROM Transactions
GROUP BY CustomerID
ORDER BY TotalSpend DESC
LIMIT 10;


-- Calculate Retention Rate: Who made transactions in consecutive years
WITH YearlyTransactions AS (
    SELECT
        CustomerID,
        YEAR(TransactionDate) AS TransactionYear
    FROM Transactions
    WHERE TransactionDate IS NOT NULL -- Ensure valid dates
    GROUP BY CustomerID, TransactionYear
)
SELECT
    yt1.TransactionYear AS Year,
    COUNT(DISTINCT yt1.CustomerID) AS ActiveCustomers,
    COUNT(DISTINCT yt2.CustomerID) AS RetainedCustomers,
    COUNT(DISTINCT yt2.CustomerID) * 100.0 / COUNT(DISTINCT yt1.CustomerID) AS RetentionRate
FROM YearlyTransactions yt1
LEFT JOIN YearlyTransactions yt2
ON yt1.CustomerID = yt2.CustomerID AND yt1.TransactionYear = yt2.TransactionYear - 1
GROUP BY yt1.TransactionYear;


-- Calculate Customer Life Time Value (CLTV) using total spend and customer lifespan
SELECT
    CustomerID,
    SUM(TransactionAmount) AS TotalSpend, -- Total amount spent by the customer
    COUNT(*) AS TotalTransactions, -- Total number of transactions
    DATEDIFF(MAX(TransactionDate), MIN(TransactionDate)) AS CustomerLifespan, -- Lifespan of a customer
    SUM(TransactionAmount) / GREATEST(DATEDIFF(MAX(TransactionDate), MIN(TransactionDate)), 1) AS CLTV -- Avoid divide by zero
FROM Transactions
GROUP BY CustomerID;


-- Calculate the average order value (AOV) 
SELECT
    AVG(TransactionAmount) AS AOV -- Average value of a transaction
FROM Transactions;



--STEP 5: SEGMENTATION ANALYSIS
--RFM (Recency, Frequency, Monetary) with Quantile Scores
WITH RFM AS (
    SELECT
        CustomerID,
        DATEDIFF(CURDATE(), MAX(TransactionDate)) AS Recency,
        COUNT(*) AS Frequency,
        SUM(TransactionAmount) AS Monetary
    FROM Transactions
    GROUP BY CustomerID
),
RFM_Scores AS (
    SELECT
        CustomerID,
        NTILE(4) OVER (ORDER BY Recency) AS RecencyScore,
        NTILE(4) OVER (ORDER BY Frequency DESC) AS FrequencyScore,
        NTILE(4) OVER (ORDER BY Monetary DESC) AS MonetaryScore
    FROM RFM
)
SELECT
    CustomerID,
    RecencyScore,
    FrequencyScore,
    MonetaryScore,
    CONCAT(RecencyScore, FrequencyScore, MonetaryScore) AS RFMScore
FROM RFM_Scores
ORDER BY RFMScore DESC;


--Customer Type Based on RFM Score:
SELECT
    CustomerID,
    CASE
        WHEN RecencyScore = 4 AND FrequencyScore = 4 AND MonetaryScore = 4 THEN 'VIP Customer'
        WHEN RecencyScore >= 3 AND FrequencyScore >= 3 THEN 'Loyal Customer'
        WHEN RecencyScore = 1 AND FrequencyScore = 1 THEN 'At Risk'
        ELSE 'Regular Customer'
    END AS CustomerType
FROM RFM_Scores;


-- Customer Segmentation by Lifetime Revenue
SELECT
    CustomerID,
    SUM(TransactionAmount) AS LifetimeRevenue,
    CASE
        WHEN SUM(TransactionAmount) >= 100000 THEN 'Platinum'
        WHEN SUM(TransactionAmount) BETWEEN 50000 AND 99999 THEN 'Gold'
        WHEN SUM(TransactionAmount) BETWEEN 10000 AND 49999 THEN 'Silver'
        ELSE 'Bronze'
    END AS RevenueSegment
FROM Transactions
GROUP BY CustomerID;

--STEP1: DATA PREPARATION 
-- Schema Creation 
-- Create the Transactions table with the necessary fields
CREATE TABLE Transactions (
    TransactionID VARCHAR(20) PRIMARY KEY, -- Unique ID for each transaction
    CustomerID VARCHAR(20), -- Unique ID for each customer
    CustomerDOB DATE, -- Customer's date of birth
    CustGender VARCHAR(10), -- Gender of the customer
    CustLocation VARCHAR(50), -- Customer's location
    CustAccountBalance DECIMAL(15, 2), -- Account balance of the customer
    TransactionDate DATE, -- Date of the transaction
    TransactionTime TIME, -- Time of the transaction
    TransactionAmount DECIMAL(15, 2) -- Transaction amount in INR
);

-- Data Cleaning 
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
    GREATEST(0, CustAccountBalance) AS CustAccountBalance, -- Ensure balance is non-negative
    STR_TO_DATE(TransactionDate, '%d/%m/%Y') AS TransactionDate, -- Convert transaction date
    SEC_TO_TIME(TransactionTime) AS TransactionTime, -- Convert transaction time
    GREATEST(0, TransactionAmount) AS TransactionAmount -- Ensure transaction amount is non-negative
FROM RawTransactions
WHERE CustomerID IS NOT NULL; -- Exclude records without CustomerID



--STEP2: DATA PROCESSING
-- (Adding Derived Fields)
--1. Calculate Customer Age 
-- Add a column for customer age
ALTER TABLE Transactions ADD COLUMN CustomerAge INT;
-- Update age based on date of birth
UPDATE Transactions
SET CustomerAge = TIMESTAMPDIFF(YEAR, CustomerDOB, CURDATE());

--2. Add Transaction Year
-- Add a column for the year of the transaction
ALTER TABLE Transactions ADD COLUMN TransactionYear INT;
-- Update the year field using the transaction date
UPDATE Transactions
SET TransactionYear = YEAR(TransactionDate);

--3. Add Age Groups
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


-- STEP:3 EXPLORATORY DATA ANALYSIS 
--1. Analyzing Transactions per Customer 
-- Get the total number of transactions for each customer
SELECT CustomerID, COUNT(*) AS TotalTransactions
FROM Transactions
GROUP BY CustomerID
ORDER BY TotalTransactions DESC;

--2. Gender-wise Spending Analysis
-- Calculate the average transaction amount by gender
SELECT CustGender, AVG(TransactionAmount) AS AvgTransactionAmount
FROM Transactions
GROUP BY CustGender;

--3. Top Revenue Generating Locations 
-- Identify top locations by total revenue
SELECT CustLocation, SUM(TransactionAmount) AS TotalRevenue
FROM Transactions
GROUP BY CustLocation
ORDER BY TotalRevenue DESC
LIMIT 10;


--STEP4: KEY METRICS EVALUATION
--1. Customer Life Time Value (CLTV)
-- Calculate CLTV using total spend and customer lifespan
SELECT
    CustomerID,
    SUM(TransactionAmount) AS TotalSpend, -- Total amount spent by the customer
    COUNT(*) AS TotalTransactions, -- Total number of transactions
    AVG(DATEDIFF(MAX(TransactionDate), MIN(TransactionDate))) AS CustomerLifespan, -- Average lifespan of a customer
    SUM(TransactionAmount) * AVG(DATEDIFF(MAX(TransactionDate), MIN(TransactionDate))) AS CLTV -- CLTV estimate
FROM Transactions
GROUP BY CustomerID;

--2. Average Order Value (AOV)
-- Calculate the average order value
SELECT
    AVG(TransactionAmount) AS AOV -- Average value of a transaction
FROM Transactions;


--STEP 5: ENHANCED SEGMENTATION
--1. Behavior based Segmentation 
-- Segment customers based on Recency, Frequency, and Spend
WITH Behavior AS (
    SELECT
        CustomerID,
        COUNT(*) AS TransactionCount, -- Total transactions per customer
        SUM(TransactionAmount) AS TotalSpend, -- Total spend per customer
        DATEDIFF(CURDATE(), MAX(TransactionDate)) AS Recency -- Days since last transaction
    FROM Transactions
    GROUP BY CustomerID
)
SELECT
    CustomerID,
    CASE
        WHEN Recency <= 30 THEN 'Recent' -- Segment customers based on recency
        WHEN Recency <= 180 THEN 'Active'
        ELSE 'Lapsed'
    END AS RecencySegment,
    CASE
        WHEN TransactionCount >= 20 THEN 'Frequent' -- Segment customers based on frequency
        WHEN TransactionCount >= 10 THEN 'Moderate'
        ELSE 'Infrequent'
    END AS FrequencySegment,
    CASE
        WHEN TotalSpend >= 100000 THEN 'High-Spender' -- Segment customers based on spending
        WHEN TotalSpend >= 50000 THEN 'Medium-Spender'
        ELSE 'Low-Spender'
    END AS SpendSegment
FROM Behavior;

--2.Seasonality Analysis:
-- Analyze transaction patterns by month
SELECT
    MONTH(TransactionDate) AS TransactionMonth, -- Extract month from the date
    COUNT(*) AS TransactionsCount, -- Count transactions per month
    SUM(TransactionAmount) AS TotalRevenue -- Total revenue per month
FROM Transactions
GROUP BY TransactionMonth
ORDER BY TransactionMonth;




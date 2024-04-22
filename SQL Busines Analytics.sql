-- 1. Calculate average number of users per customer ID

WITH TotalUsersPerCustomer AS (
SELECT SUM(NumberOfUsers) as TotUsers, CustomerID
FROM subscriptions
GROUP BY CustomerID
)

SELECT AVG(TotUsers), CustomerID
FROM TotalUsersPerCustomer


-- 2. Leadership wants to understand the distribution of monthly revenue across 2022.
-- To do so let's calculate the minimum monthly revenue, maximum monthly revenue, average monthly revenue, and standard deviation of monthly revenue for each product for orders in 2022

WITH MonthlyRevByProd AS (
SELECT p.ProductName, SUM(s.Revenue) Rev, DATE_TRUNC('month',s.OrderDate)
FROM Products p
JOIN Subscriptions s
ON s.ProductID = p.ProductID
WHERE YEAR(s.OrderDate) = '2022'
GROUP BY p.PRODUCTNAME, DATE_TRUNC('month',s.OrderDate)
)

SELECT ProductName, MAX(Rev) as max_rev, MIN(Rev) as min_rev, AVG(Rev) as avg_rev, STDDEV(Rev) as std_dev_rev
FROM MonthlyRevByProd
GROUP BY ProductName


-- 3. A manager on the marketing team is asking about the performance of their recent email campaign. Now that the campaign has been launced, the manager wants to know how many users have clicked the link in the email.
-- An email link click is indentified by an EventID being equal to 5
-- Since a metric like average can hide outliers, let's calculate the distribution of the number of email link clicks per user

WITH CntClicksByUser AS (
SELECT COUNT(1) as NUM_LINK_CLICKS, UserID
FROM FrontendEventLog
WHERE EventID = 5
GROUP BY UserID)

SELECT COUNT(UserID) as NUM_USERS, NUM_LINK_CLICKS
FROM CntClicksByUser
GROUP BY NUM_LINK_CLICKS


-- 4. The Product Manager has requested a payment funnel analysis. They want to understand what the furthest point in the payment process users are getting to before dropping out is. They want visibility into each stage from the user's point of view.

WITH MaxStatus AS (
	SELECT 
	MAX(StatusID) maxstatus, ps.SubscriptionID
	FROM PaymentStatusLog ps
	GROUP BY ps.SubscriptionID
),
PaymentFunnel AS (
	SELECT s.SubscriptionID,
		CASE
			WHEN maxstatus = 1 THEN 'PaymentWidgetOpened'
			WHEN maxstatus = 2 THEN 'PaymentEntered'
			WHEN maxstatus = 3 AND currentstatus = 0 THEN 'User Error with Payment Submission'
			WHEN maxstatus = 3 AND currentstatus != 0 THEN 'Payment Submitted'
			WHEN maxstatus = 4 AND currentstatus = 0 THEN 'Payment Processing Error with Vendor'
			WHEN maxstatus = 4 AND currentstatus != 0 THEN 'Payment Success'
			WHEN maxstatus = 5 THEN 'Complete'
			WHEN maxstatus is null THEN 'User did not start payment process'
		END as paymentfunnelstage
	FROM Subscriptions s
	LEFT JOIN MaxStatus ms
	ON ms.SubscriptionID = s.SubscriptionID
)

SELECT paymentfunnelstage, COUNT(SubscriptionID) subscriptions
FROM PaymentFunnel
GROUP BY paymentfunnelstage


-- 5. The product team is launching a new product offering that can be added to a current subscription for an increase in annual fee. The sales team has decided they want to reach out to a spcific group of customers to test the new product offering. They decided they want to target customers who have either 5,000 registered users or only one product subscription
-- Create a report of customers who meet these criteria

SELECT
    customerid,
    COUNT(ProductID) num_products,
    SUM(NumberofUsers) total_users,
    CASE
        WHEN SUM(NumberofUsers) > 5000 THEN 1
        WHEN COUNT(ProductID) = 1 THEN 1
        ELSE 0
    END as upsell_opportunity
FROM subscriptions
GROUP BY customerid


-- 6. The design team has redesigned the customer support page and wants to run an A/B test to see how the newly desgined page performs compared to the original. To do so we need to track user activity via frontend events.
-- It will be important to track user activity and ticket submissions on the customer support page since they could be impacted by design changes. We will track when a user: views help center, clicks FAQs, clicks contact support, submits ticket. 

SELECT UserID,
    SUM(CASE WHEN l.eventid = 1 THEN 1 ELSE 0 END) AS ViewedHelpCenterPage,
    SUM(CASE WHEN l.eventid = 2 THEN 1 ELSE 0 END) AS ClickedFAQs,
    SUM(CASE WHEN l.eventid = 3 THEN 1 ELSE 0 END) AS ClickedContactSupport,
    SUM(CASE WHEN l.eventid = 4 THEN 1 ELSE 0 END) AS SubmittedTicket,
FROM frontendeventlog l
JOIN frontendeventdefinitions d
ON d.EVENTID = l.EVENTID
WHERE d.eventtype = 'Customer Support'
GROUP BY USERID


-- 7. The growth team is focused on reducing churn. They are planning on launching multiple campaigns to drive users to renew subscriptions. They are first conducting research to understand when all active subscriptions are going to expire. Because of modelling limitations the data is stored in multiple tables. 
-- We want to find the number of active subscriptions that will expire each year

WITH all_subscriptions AS (
SELECT 
	CustomerID,
	ExpirationDate
FROM SubscriptionsProduct1
WHERE Active = 1 

UNION

SELECT
	CustomerID,
	ExpirationDate
FROM SubscriptionsProduct2
WHERE Active = 1
)
select 
	DATE_TRUNC('year', expirationdate) as exp_year,
	COUNT(*) as subscriptions
FROM all_subscriptions
GROUP BY
	DATE_TRUNC('year', expirationdate)


-- 8. Since the growth team is concerned with churn, one of their questions is 'why are customers not renewing?. Particularly, they want percent of customers are churning due to cost.
-- To answer this question, we will look at the amount of customers who selected 'Expensive' as one of the reasons they did cancelled. 


WITH all_cancellation_reasons AS (
SELECT 
    SubscriptionID,
    CancellationReason1
FROM Cancellations

UNION

SELECT 
    SubscriptionID,
    CancellationReason2
FROM Cancellations

UNION

SELECT 
    SubscriptionID,
    CancellationReason1
FROM Cancellations
)
SELECT 
    CAST(COUNT(
        CASE WHEN CancellationReason1 = 'Expensive' THEN 1 END) AS FLOAT) /
    COUNT(DISTINCT subscriptionid) as percent_expensive
FROM all_cancellation_reasons


-- 9. The VP of sales is currently contacting all of the managers who have direct reports in the Sales department to notify them of the new comission structure.
-- Some of the employees have NULL values for the managerID, to address this issue we will contact the employee directly if their managerID is null to ensure they do not miss out on the message

SELECT
    emp.employeeid as employeeid,
    emp.name as employee_name,
    mgr.name as manager_name,
    COALESCE(mgr.email, emp.email) as contact_email,
FROM 
    employees emp
LEFT JOIN 
    employees mgr
ON emp.managerid = mgr.EMPLOYEEID
WHERE emp.department = 'Sales'


-- 10. Year end reporting is coming about and the sales manager wants to see month over month revenue trends and highlight months where revenue was greater than the previous month.


WITH MonthlyRev AS (
SELECT
    DATE_TRUNC('month', orderdate) as order_month,
    SUM(revenue) as monthly_revenue
FROM subscriptions
GROUP BY DATE_TRUNC('month', orderdate)
)

SELECT 
    CurrentMonth.order_month as current_month,
    PreviousMonth.order_month as previous_month,
    CurrentMonth.monthly_revenue as current_revenue,
    PreviousMonth.monthly_revenue as previous_revenue
FROM MonthlyRev CurrentMonth
JOIN MonthlyRev PreviousMonth 
WHERE 
    CurrentMonth.monthly_revenue > PreviousMonth.monthly_revenue
    AND
    DATEDIFF('month', PreviousMonth.order_month, CurrentMonth.order_month) = 1


-- 11. The sales manager wants to check on sales team activity to see what reps are performing well and which reps may need some coaching. Particularly, they want to see the most recent close date of each seller

WITH SalesData AS (
SELECT 
    SaleID,
    SalesEmployeeID,
    SaleDate,
    SaleAmount,
    ROW_NUMBER() OVER (PARTITION BY SalesEmployeeID ORDER BY SaleDate DESC) as MostRecentSale
FROM Sales
)

SELECT *
FROM SalesData
WHERE MostRecentSale = 1


-- 12. Now, the sales manager wants to track each sales member's performance throughout the year. They want to see how each member is progressing through the year.
-- To show how they are progressing through the year we can use a running total and a percent quota achieved.

SELECT
    SalesEmployeeID,
    SaleDate,
    SaleAmount,
    SUM(SaleAmount) OVER (PARTITION BY SalesEmployeeID ORDER BY SaleDate ASC) as running_total,
    CAST(SUM(SaleAmount) OVER (PARTITION BY SalesEmployeeID ORDER BY SaleDate) AS FLOAT) / Quota  as percent_quota
FROM Sales s
JOIN Employees e
ON s.SalesEmployeeID = e.EmployeeID
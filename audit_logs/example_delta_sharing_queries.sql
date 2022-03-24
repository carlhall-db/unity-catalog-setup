-- Databricks notebook source
-- MAGIC %md
-- MAGIC ### Create Filters - Audit Log Tables and Date Range

-- COMMAND ----------

CREATE WIDGET TEXT 0_catalog DEFAULT "audit_logs";

CREATE WIDGET TEXT 0_database DEFAULT "aws";

CREATE WIDGET TEXT 1_Date_Begin DEFAULT "2021-11-24";

CREATE WIDGET TEXT 2_Date_End DEFAULT "2022-12-31";

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Select appropriate catalog & database

-- COMMAND ----------

USE $0_catalog.$0_database

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 
-- MAGIC ### Create Filters - Queries

-- COMMAND ----------

--create widget for multiple selections of recipient names generated on run of this notebook for latest list from latest data
CREATE WIDGET DROPDOWN 4_Recipients DEFAULT "N/A" CHOICES
SELECT
  DISTINCT CASE
    WHEN requestParams.recipient_name is null THEN "N/A"
    else requestParams.recipient_name
  END as recipient_name
FROM
  unitycatalog;
  
-- Create Widget for Actions Wanted to Visualize
  CREATE WIDGET DROPDOWN 5_Shares DEFAULT "N/A" CHOICES
SELECT
  DISTINCT CASE
    WHEN requestParams.share is null THEN "N/A"
    else requestParams.share
  END as `Share Name`
FROM
  unitycatalog;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Recipient details

-- COMMAND ----------

DESCRIBE RECIPIENT $4_Recipients

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Current Share Assets

-- COMMAND ----------

SHOW ALL IN SHARE $5_Shares

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Recipients Current Accessibility to Share(s)

-- COMMAND ----------

SHOW GRANT TO RECIPIENT $4_Recipients

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Recipient Information (Who and When it was created, current permissions, last modified, first & last use)

-- COMMAND ----------

Select
  Name as `Recipient`,
  created_by as `Created By`,
  `First Used`,
  `Last Used`,
  `Successful %`,
  `Total Failed`,
  `Total Successful`,
  `Total` as `Total Actions`,
  `activation_link` as `Activation Link`,
  active_token_id as `Active Token ID`,
  date_format(active_token_expiration_time, "yyyy-mm-dd") as `Active Token Expiration`,
  rotated_token_id as `Rotated Token`,
  rotated_token_expiration_time as `Rotated Token Expiration`,
  comment as `Comment`
FROM
  recipient r
  LEFT JOIN (
    SELECT
      requestParams.recipient_name as recipient_name,
      MIN(date) as `First Used`,
      MAX(date) as `Last Used`,
      format_number(
        (
          SUM(
            (
              CASE
                WHEN response.statusCode = "200" THEN 1
                ELSE 0
              END
            )
          ) / count(lower(actionName))
        ),
        "#%"
      ) as `Successful %`,
      SUM(
        (
          CASE
            WHEN response.statusCode <> "200" THEN 1
            ELSE 0
          END
        )
      ) as `Total Failed`,
      SUM(
        (
          CASE
            WHEN response.statusCode = "200" THEN 1
            ELSE 0
          END
        )
      ) as `Total Successful`,
      count(lower(actionName)) as `Total`
    from
      unitycatalog
    group by
      requestParams.recipient_name
    order by
      `Total` desc
  ) u on u.recipient_name = r.Name

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Total Activity and Failure Ratio per Recipient

-- COMMAND ----------

--last week or last two weeks (what you care about for failures)
SELECT
  requestParams.recipient_name,
  email,
  lower(actionName) as `Actions`,
  MIN(date) as `First Used`,
  MAX(date) as `Last Used`,
  format_number(
    (
      SUM(
        (
          CASE
            WHEN response.statusCode = "200" THEN 1
            ELSE 0
          END
        )
      ) / count(lower(actionName))
    ),
    "#%"
  ) as `Successful %`,
  count(lower(actionName)) as `Total`,
  SUM(
    (
      CASE
        WHEN response.statusCode = "400" THEN 1
        ELSE 0
      END
    )
  ) as `Client Error`,
  SUM(
    (
      CASE
        WHEN response.statusCode = "403" THEN 1
        ELSE 0
      END
    )
  ) as `Access Error`,
  SUM(
    (
      CASE
        WHEN response.statusCode = "404" THEN 1
        ELSE 0
      END
    )
  ) as `Not Found Error`,
  SUM(
    (
      CASE
        WHEN response.statusCode <> "200" THEN 1
        ELSE 0
      END
    )
  ) as `Total Failed`,
  SUM(
    (
      CASE
        WHEN response.statusCode = "200" THEN 1
        ELSE 0
      END
    )
  ) as `Total Successful`
from
  unitycatalog
where
  requestParams.recipient_name LIKE '%$4_Recipients%'
  AND requestParams.share LIKE '%$5_Shares%'
  AND (
    date >= getArgument("1_Date_Begin")
    AND date <= getArgument('2_Date_End')
  )
group by
  lower(actionName),
  email,
  requestParams.recipient_name
order by
  `Total Failed` desc

-- COMMAND ----------

-- DBTITLE 1,Recipient Error Frequency
-- date table to make sure you get days without errors and a full time series
select
  requestParams.recipient_name,
  date,
  response.statusCode,
  count(*) as numErrors
from
  unitycatalog
where
  response.statusCode <> 200
  AND requestParams.recipient_name LIKE '%$4_Recipients%'
  AND requestParams.share LIKE '%$5_Shares%'
  AND (
    date >= getArgument("1_Date_Begin")
    AND date <= getArgument('2_Date_End')
  )
group by
  1,
  2,
  3
order by
  date;

-- COMMAND ----------

-- DBTITLE 1,Recipient IPAddresses
-- group by CIDR range, (different CIDR)
-- find geography of ip ranges, service where IP came from? python packages (virtual SAs/my friends)
-- IP ranges & geographies put into the graph
select
  requestParams.recipient_name,
  date,
  sourceIpAddress,
  count(*) as numQueries
from
  unitycatalog
where
  requestParams.recipient_name is not null --and (actionName like "%deltaSharing%")
  and sourceIpAddress is not null
  AND requestParams.recipient_name LIKE '%$4_Recipients%'
  AND requestParams.share LIKE '%$5_Shares%'
  AND (
    date >= getArgument("1_Date_Begin")
    AND date <= getArgument('2_Date_End')
  )
group by
  1,
  2,
  3
order by
  4;

-- COMMAND ----------

-- DBTITLE 1,Recipient Error Details
-- agent, time, error message, IP address, response
--last week or last two weeks (what you care about for failures)
SELECT
  u.date,
  email,
  requestParams.recipient_name,
  lower(actionName) as `Actions`,
  count(lower(actionName)) as `Total Failures`,
  response.statusCode,
  CASE
    WHEN response.statusCode = "400" THEN "Client Error"
    ELSE CASE
      WHEN response.statusCode = "403" THEN "Access Error"
      ELSE CASE
        WHEN response.statusCode = "404" THEN "Not Found Error"
        ELSE CASE
          WHEN response.statusCode = "200" THEN "Success"
          ELSE response.statusCode
        END
      END
    END
  END as Responses,
  response.errorMessage,
  response.result,
  sourceIPAddress,
  CASE
    WHEN userAgent is NULL THEN requestParams.user_agent
    ELSE userAgent
  END as `User Agent`,
  requestParams
from
  unitycatalog u
where
  response.statusCode <> "200"
  AND requestParams.recipient_name LIKE '%$4_Recipients%'
  AND requestParams.share LIKE '%$5_Shares%'
  AND (
    date >= getArgument("1_Date_Begin")
    AND date <= getArgument('2_Date_End')
  )
group by
  email,
  lower(actionName),
  date,
  response.errorMessage,
  response.statusCode,
  sourceIPAddress,
  response.result,
  userAgent,
  requestParams
order by
  date desc

-- COMMAND ----------

-- DBTITLE 1,Recipient Query Data Frequency
--query
-- notifications of table versions
-- metadata vs. query
select
  requestParams.recipient_name,
  date,
  count(*) as numQueries
from
  unitycatalog
where
  LOWER(actionName) like "deltasharingquer%"
  AND requestParams.recipient_name LIKE '%$4_Recipients%'
  AND requestParams.share LIKE '%$5_Shares%'
  AND (
    date >= getArgument("1_Date_Begin")
    AND date <= getArgument('2_Date_End')
  )
group by
  1,
  2
order by
  date asc

-- COMMAND ----------

-- DBTITLE 1,Recipient Activities by Agent
--
select
  recipient_name,
  date,
  `User Agent`,
  num_actions
from
  (
    select
      requestParams.recipient_name as recipient_name,
      date,CASE
        WHEN userAgent is NULL THEN requestParams.user_agent
        ELSE userAgent
      END as `User Agent`,
      count(*) as num_actions
    from
      unityCatalog
    WHERE
      requestParams.recipient_name LIKE '%$4_Recipients%'
      AND requestParams.share LIKE '%$5_Shares%'
      AND (
        date >= getArgument("1_Date_Begin")
        AND date <= getArgument('2_Date_End')
      )
    group by
      requestParams.recipient_name,
      date,
      userAgent,
      requestParams
    order by
      date DESC,
      num_actions DESC
  )
where
  num_actions > 0;

-- COMMAND ----------

-- DBTITLE 1,Recipient Activities
select
  recipient_name,
  date,
  actionName,
  num_actions
from
  (
    select
      requestParams.recipient_name as recipient_name,
      date,
      actionName,
      count(*) as num_actions
    from
      unityCatalog
    WHERE
      requestParams.recipient_name LIKE '%$4_Recipients%'
      AND requestParams.share LIKE '%$5_Shares%'
      AND (
        date >= getArgument("1_Date_Begin")
        AND date <= getArgument('2_Date_End')
      )
    group by
      requestParams.recipient_name,
      date,
      requestParams,
      actionName
    order by
      date DESC,
      num_actions DESC
  )
where
  num_actions > 0;

-- COMMAND ----------

-- DBTITLE 1,Recipients Top Tables
--action item ask lin what "queriedtable"
-- hierarchy calc (english sentence), concat the three level namespace and give an explanation
SELECT
  DISTINCT --actionName,
  CASE
    WHEN CONCAT(
      requestParams.share,
      ".",
      requestParams.schema,
      ".",
      requestParams.name
    ) is null THEN CAST(
      from_json(response.result, 'tableName STRING').tableName AS STRING
    )
    ELSE CONCAT(
      requestParams.share,
      ".",
      requestParams.schema,
      ".",
      requestParams.name
    )
  END as Asset,
  date,
  MIN(date) as `First Usage Date`,
  MAX(date) as `Max Usage Date`,
  CASE
    WHEN response.statusCode = "200" THEN count(actionName)
    ELSE 0
  END as `Successful Actions`,
  CASE
    WHEN response.statusCode = "403" THEN count(actionName)
    ELSE ""
  END as `Failed Actions`,
  count(actionName) as `Total Actions`,
  format_number(
    (
      CASE
        WHEN response.statusCode = "200" THEN count(actionName)
        ELSE 0
      END / count(actionName)
    ),
    "#%"
  ) as `Percent Successful`
from
  unitycatalog
where
  (
    CASE
      WHEN CONCAT(
        requestParams.share,
        requestParams.schema,
        requestParams.name
      ) IS NULL THEN CAST(
        from_json(response.result, 'tableName STRING').tableName AS STRING
      )
      ELSE CONCAT(
        requestParams.share,
        requestParams.schema,
        requestParams.name
      )
    END
  ) is not null
  AND requestParams.recipient_name LIKE '%$4_Recipients%'
  AND requestParams.share LIKE '%$5_Shares%'
  AND (
    date >= getArgument("1_Date_Begin")
    AND date <= getArgument('2_Date_End')
  )
group by
  requestParams,
  --actionName,
  response,
  date
order by
  `Total Actions` desc
limit
  10

-- COMMAND ----------

-- DBTITLE 1,# Bytes of Shared Data Recipients are Accessing (Starting 11/05)
select
  recipient_name,
  tableName,
  date,
  sum(numBytes) as numBytes
from
  (
    select
      requestParams.recipient_name as recipient_name,
      date,
      --CONCAT(requestParams.share,requestParams.schema,requestParams.name) as Share_Database_Table,date,
      CAST(
        from_json(response.result, 'tableName STRING').tableName AS STRING
      ) as tableName,
      CAST(
        from_json(response.result, 'scannedAddFileSize STRING').scannedAddFileSize AS BIGINT
      ) as numBytes,
      CAST(
        from_json(response.result, 'numRecords STRING').numRecords AS BIGINT
      ) as numRecords,
      CAST(
        from_json(response.result, 'activeAddFiles STRING').activeAddFiles AS BIGINT
      ) as numFiles,
      actionName
    from
      unitycatalog
    WHERE
      LOWER(actionName) = "deltasharingqueriedtable"
      AND requestParams.recipient_name LIKE '%$4_Recipients%'
      AND (
        date >= getArgument("1_Date_Begin")
        AND date <= getArgument('2_Date_End')
      )
  )
WHERE
  numBytes is not null
group by
  recipient_name,
  tableName,
  date
order by
  numBytes desc;

-- COMMAND ----------

select
  requestParams.recipient_name as recipient_name,
  date,
  actionName,
  CAST(
    from_json(response.result, 'metastoreId STRING').metastoreId AS STRING
  ) as metastoreId,
  CAST(
    from_json(response.result, 'tableName STRING').tableName AS STRING
  ) as tableName,
  CAST(
    from_json(response.result, 'checkpointBytes STRING').checkpointBytes AS BIGINT
  ) as checkpointBytes,
  CAST(
    from_json(response.result, 'maxRemoveFiles STRING').maxRemoveFiles AS BIGINT
  ) as maxRemoveFiles,
  CAST(
    from_json(response.result, 'path STRING').path AS STRING
  ) as filepath,
  CAST(
    from_json(response.result, 'scannedAddFileSize STRING').scannedAddFileSize AS BIGINT
  ) as numBytes,
  CAST(
    from_json(response.result, 'numRecords STRING').numRecords AS BIGINT
  ) as numRecords,
  CAST(
    from_json(response.result, 'activeAddFiles STRING').activeAddFiles AS BIGINT
  ) as numFiles,
  CAST(
    from_json(response.result, 'limitHint STRING').limitHint AS STRING
  ) as limitHint
from
  unitycatalog
where
  LOWER(actionName) = "deltasharingqueriedtable"
  and requestParams.recipient_name LIKE '%$4_Recipients%'
  AND (
    date >= getArgument("1_Date_Begin")
    AND date <= getArgument('2_Date_End')
  )

-- COMMAND ----------

-- DBTITLE 1,Amount of Shared Data Recipients are Accessing (Starting 11/05)
-- no user agent with queried table
select
  recipient_name,
  actionName,
  date,
  sum(numBytes) as numBytes,
  sum(numRecords) as numRecords,
  sum(numFiles) as numFiles
from
  (
    select
      requestParams.recipient_name as recipient_name,
      date,
      CAST(
        from_json(response.result, 'scannedAddFileSize STRING').scannedAddFileSize AS BIGINT
      ) as numBytes,
      CAST(
        from_json(response.result, 'numRecords STRING').numRecords AS BIGINT
      ) as numRecords,
      CAST(
        from_json(response.result, 'activeAddFiles STRING').activeAddFiles AS BIGINT
      ) as numFiles,
      actionName
    from
      unitycatalog
    WHERE
      LOWER(actionName) = "deltasharingqueriedtable"
      AND requestParams.recipient_name LIKE '%$4_Recipients%'
      AND (
        date >= getArgument("1_Date_Begin")
        AND date <= getArgument('2_Date_End')
      )
  )
group by
  recipient_name,
  date,
  actionName
order by
  date DESC,
  numBytes desc;

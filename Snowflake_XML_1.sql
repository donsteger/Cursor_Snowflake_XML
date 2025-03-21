-- Snowflake XML Processing Workflow
-- This script demonstrates the end-to-end process of loading and querying XML files in Snowflake

-- Step 1: Create a database and schema for our XML processing
CREATE DATABASE IF NOT EXISTS xml_processing;
USE DATABASE xml_processing;
CREATE SCHEMA IF NOT EXISTS raw_data;
USE SCHEMA raw_data;

-- Step 2: Create a file format for XML files
CREATE OR REPLACE FILE FORMAT xml_format
    TYPE = 'XML'
    STRIP_OUTER_ELEMENT = FALSE
    PRESERVE_SPACE = TRUE;

-- Step 3: Create an internal stage to store our XML files
CREATE OR REPLACE STAGE xml_stage
    FILE_FORMAT = xml_format;

-- Step 3a: Upload XML files to the stage using SnowSQL CLI
-- 1. Install SnowSQL CLI from https://docs.snowflake.com/en/user-guide/snowsql-install-config
-- 2. Connect to your Snowflake account using the command:
--    snowsql -a <your_account_identifier> -u <your_username> -d xml_processing -s raw_data
--    For example: snowsql -a xy12345.us-east-1 -u jsmith -d xml_processing -s raw_data
-- 3. When prompted, enter your password
-- 4. Once connected, use the PUT command to upload your XML files:
--    PUT file://C:/path/to/your/xml/files/*.xml @xml_stage;
--    For Mac/Linux: PUT file:///home/user/path/to/xml/files/*.xml @xml_stage;
-- 5. Verify the files were uploaded successfully with:
--    LIST @xml_stage;
-- 6. Exit SnowSQL when finished by typing: !exit

-- Step 3b: Alternative Method 1 - Using Snowflake Web UI
-- 1. Log in to Snowflake web interface
-- 2. Navigate to Data > Databases > XML_PROCESSING > RAW_DATA
-- 3. Click on Stages, then select XML_STAGE
-- 4. Click the "Upload" button
-- 5. Select your XML files from your local machine and upload
-- 6. Verify files appear in the stage listing

-- Step 3c: Alternative Method 2 - Using Snowflake Python Connector
-- 1. Install the Snowflake Python connector: pip install snowflake-connector-python
-- 2. Create a Python script like this:
--    ```python
--    import snowflake.connector
--    import os
--    
--    # Connect to Snowflake
--    conn = snowflake.connector.connect(
--        user='your_username',
--        password='your_password',
--        account='your_account_identifier',
--        warehouse='your_warehouse',
--        database='XML_PROCESSING',
--        schema='RAW_DATA'
--    )
--    
--    # Create a cursor
--    cursor = conn.cursor()
--    
--    # Path to your XML files
--    xml_dir = '/path/to/your/xml/files/'
--    
--    # Upload each XML file in the directory
--    for file in os.listdir(xml_dir):
--        if file.endswith('.xml'):
--            put_command = f"PUT file://{os.path.join(xml_dir, file)} @xml_stage AUTO_COMPRESS=FALSE"
--            cursor.execute(put_command)
--    
--    # Verify files were uploaded
--    cursor.execute("LIST @xml_stage")
--    for file in cursor:
--        print(file)
--    
--    # Close the connection
--    cursor.close()
--    conn.close()
--    ```
--    3. Run the Python script to upload your files

-- Step 3d: Alternative Method 3 - Using JDBC/ODBC Driver
-- 1. Install the appropriate JDBC or ODBC driver for your environment
-- 2. Connect to Snowflake using your preferred client application
-- 3. Execute PUT commands similar to the SnowSQL method:
--    PUT file:///path/to/your/xml/files/*.xml @xml_stage;
-- 4. Verify with: LIST @xml_stage;

-- Step 4: Create a raw table to store XML content
CREATE OR REPLACE TABLE raw_xml_orders (
    file_name VARCHAR,
    upload_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    raw_xml VARIANT
);

-- Step 5: Load XML files from stage into the raw table
COPY INTO raw_xml_orders (file_name, raw_xml)
FROM (
    SELECT METADATA$FILENAME, $1
    FROM @xml_stage
)
FILE_FORMAT = xml_format
PATTERN = '.*\.xml'
ON_ERROR = 'CONTINUE';

-- Step 6: Create normalized tables for better querying
-- Orders Header Table
CREATE OR REPLACE TABLE orders_header AS
SELECT 
    raw_xml:Order.OrderHeader.OrderNumber.BuyerOrderNumber::STRING as buyer_order_number,
    raw_xml:Order.OrderHeader.OrderIssueDate::TIMESTAMP_NTZ as order_issue_date,
    raw_xml:Order.OrderHeader.OrderReferences.AccountCode.core:RefNum::STRING as account_code,
    file_name as source_file,
    upload_timestamp
FROM raw_xml_orders;

-- Example queries to extract specific XML data
-- Query 1: Get all order numbers and dates
SELECT 
    buyer_order_number,
    order_issue_date,
    account_code
FROM orders_header
ORDER BY order_issue_date DESC;

-- Query 2: Parse nested XML elements using FLATTEN
-- This example shows how to handle repeating elements if they exist in the XML
SELECT 
    buyer_order_number,
    f.value:core:ReferenceTypeCoded::STRING as reference_type,
    f.value:core:PrimaryReference.core:RefNum::STRING as reference_number
FROM raw_xml_orders,
LATERAL FLATTEN(input => raw_xml:Order.OrderHeader.OrderReferences.OtherOrderReferences.core:ReferenceCoded) f;

-- Best Practices and Recommendations:
/*
1. Staging Approach:
   - Always load raw XML into a VARIANT column first
   - Create normalized views or tables for frequently accessed data
   - Keep the raw XML for future needs or schema changes

2. Performance Optimization:
   - Create appropriate clustering keys on frequently queried columns
   - Materialize commonly used queries into tables
   - Use FLATTEN for nested arrays/repeating elements

3. Monitoring and Maintenance:
   - Track file loading success/failures
   - Monitor storage usage
   - Implement error handling for malformed XML

4. Security:
   - Implement appropriate access controls
   - Consider data retention policies
   - Mask sensitive data if needed
*/

-- Create a view for monitoring load status
CREATE OR REPLACE VIEW v_xml_load_status AS
SELECT 
    DATE_TRUNC('day', upload_timestamp) as load_date,
    COUNT(*) as files_loaded,
    COUNT(DISTINCT file_name) as unique_files,
    MIN(upload_timestamp) as first_load,
    MAX(upload_timestamp) as last_load
FROM raw_xml_orders
GROUP BY 1
ORDER BY 1 DESC; 
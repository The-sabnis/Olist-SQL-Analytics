/* =====================================================================
   01_create_tables.sql
   Project : Olist Retail Analytics (OlistRetailDB, schema ctr)
   Purpose : Table definitions, keys and design decisions
   Design  : load first, clean second (loose types at load, validate after)
             zip codes = varchar (no math, leading zeros)
             money = DECIMAL(10,2), never FLOAT
             coordinates = DECIMAL(18,8)
             all constraints explicitly named
   ===================================================================== */
USE OlistRetailDB;
GO
IF SCHEMA_ID('ctr') IS NULL EXEC('CREATE SCHEMA ctr');
GO

-- 1. customers (99,441 rows)
-- customer_unique_id is NOT unique by design: one person, many orders,
-- each with a new customer_id (2,997 repeat customers, worst case 17 orders)
/****** Object:  Table [ctr].[customers]    Script Date: 10/23/2026 4:55:04 PM ******/

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[customers](
	[customer_id] [varchar](50) NOT NULL,
	[customer_unique_id] [varchar](50) NULL,
	[customer_zip_code_prefix] [varchar](15) NULL,
	[customer_city] [varchar](100) NOT NULL,
	[customer_state] [varchar](5) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[customer_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Represents the real customer. NOT unique by design — one person can place multiple orders, each generating a new customer_id. Confirmed via data investigation (see GitHub README).' , @level0type=N'SCHEMA',@level0name=N'ctr', @level1type=N'TABLE',@level1name=N'customers', @level2type=N'COLUMN',@level2name=N'customer_unique_id'
GO

-- 2. orders (99,441 rows)
-- NOTE: column order must match the CSV for BULK INSERT (it maps by position).
-- This was the cause of the silent misalignment bug (see README).

/****** Object:  Table [ctr].[orders]    Script Date: 10/23/2026 5:06:11 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[orders](
	[order_id] [varchar](50) NOT NULL,
	[order_status] [varchar](50) NOT NULL,
	[order_purchase_timestamp] [datetime2](0) NOT NULL,
	[order_approved_at] [datetime2](0) NULL,
	[order_delivered_carrier_date] [datetime2](0) NULL,
	[order_delivered_customer_date] [datetime2](0) NULL,
	[order_estimated_delivery_date] [datetime2](0) NOT NULL,
	[customer_id] [varchar](50) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[order_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [ctr].[orders]  WITH NOCHECK ADD  CONSTRAINT [fk_orders_customers] FOREIGN KEY([customer_id])
REFERENCES [ctr].[customers] ([customer_id])
GO

ALTER TABLE [ctr].[orders] CHECK CONSTRAINT [fk_orders_customers]
GO


-- 3. products (32,951 rows)  ("lenght" spelling is from the source)

/****** Object:  Table [ctr].[products]    Script Date: 10/23/2026 5:10:27 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[products](
	[product_id] [varchar](50) NOT NULL,
	[product_category_name] [varchar](100) NULL,
	[product_name_lenght] [int] NULL,
	[product_description_lenght] [int] NULL,
	[product_photos_qty] [int] NULL,
	[product_weight_g] [decimal](10, 2) NULL,
	[product_length_cm] [decimal](10, 2) NULL,
	[product_height_cm] [decimal](10, 2) NULL,
	[product_width_cm] [decimal](10, 2) NULL,
PRIMARY KEY CLUSTERED 
(
	[product_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


-- 4. sellers (3,095 rows)
/****** Object:  Table [ctr].[sellers]    Script Date: 10/23/2026 5:15:11 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[sellers](
	[seller_id] [varchar](50) NOT NULL,
	[seller_zip_code_prefix] [varchar](10) NULL,
	[seller_city] [varchar](50) NOT NULL,
	[seller_state] [varchar](5) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[seller_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


-- 5. order_items (112,650 rows) - bridge table; quantity = row count
-- product_id / seller_id are varchar(50) to match the parent keys (FKs need equal length)

/****** Object:  Table [ctr].[order_items]    Script Date: 10/23/2026 5:01:44 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[order_items](
	[order_id] [varchar](50) NOT NULL,
	[order_item_id] [int] NOT NULL,
	[product_id] [varchar](50) NOT NULL,
	[seller_id] [varchar](50) NOT NULL,
	[price] [decimal](10, 2) NOT NULL,
	[freight_value] [decimal](10, 2) NOT NULL,
	[shipping_limit_date] [datetime2](0) NULL,
 CONSTRAINT [pk_order_items] PRIMARY KEY CLUSTERED 
(
	[order_id] ASC,
	[order_item_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [ctr].[order_items]  WITH CHECK ADD  CONSTRAINT [fk_order_item_product] FOREIGN KEY([product_id])
REFERENCES [ctr].[products] ([product_id])
GO

ALTER TABLE [ctr].[order_items] CHECK CONSTRAINT [fk_order_item_product]
GO

ALTER TABLE [ctr].[order_items]  WITH CHECK ADD  CONSTRAINT [fk_order_item_seller] FOREIGN KEY([seller_id])
REFERENCES [ctr].[sellers] ([seller_id])
GO

ALTER TABLE [ctr].[order_items] CHECK CONSTRAINT [fk_order_item_seller]
GO

ALTER TABLE [ctr].[order_items]  WITH CHECK ADD  CONSTRAINT [fk_orders_item] FOREIGN KEY([order_id])
REFERENCES [ctr].[orders] ([order_id])
GO

ALTER TABLE [ctr].[order_items] CHECK CONSTRAINT [fk_orders_item]
GO


-- 6. order_payments (103,886 rows)

/****** Object:  Table [ctr].[order_payments]    Script Date: 10/23/2026 5:03:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[order_payments](
	[order_id] [varchar](50) NOT NULL,
	[payment_sequential] [int] NOT NULL,
	[payment_type] [varchar](20) NOT NULL,
	[payment_installments] [int] NOT NULL,
	[payment_value] [decimal](10, 2) NOT NULL,
 CONSTRAINT [pk_order_payments] PRIMARY KEY CLUSTERED 
(
	[order_id] ASC,
	[payment_sequential] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [ctr].[order_payments]  WITH CHECK ADD  CONSTRAINT [fk_order_payments_orders] FOREIGN KEY([order_id])
REFERENCES [ctr].[orders] ([order_id])
GO

ALTER TABLE [ctr].[order_payments] CHECK CONSTRAINT [fk_order_payments_orders]
GO

-- 7. order_reviews (99,224 rows)
-- composite PK: one review_id is shared by two orders in the source (25 such ids)

/****** Object:  Table [ctr].[order_reviews]    Script Date: 10/23/2026 5:04:15 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[order_reviews](
	[review_id] [varchar](50) NOT NULL,
	[order_id] [varchar](50) NOT NULL,
	[review_score] [int] NULL,
	[review_comment_title] [varchar](100) NULL,
	[review_comment_message] [nvarchar](1000) NULL,
	[review_creation_date] [datetime] NOT NULL,
	[review_answer_timestamp] [datetime] NOT NULL,
 CONSTRAINT [pk_order_reviews] PRIMARY KEY CLUSTERED 
(
	[review_id] ASC,
	[order_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [ctr].[order_reviews]  WITH CHECK ADD  CONSTRAINT [fk_order_review] FOREIGN KEY([order_id])
REFERENCES [ctr].[orders] ([order_id])
GO

ALTER TABLE [ctr].[order_reviews] CHECK CONSTRAINT [fk_order_review]
GO

-- 8. geolocation (1,000,163 rows) - no PK: one zip maps to many lat/lng points
/****** Object:  Table [ctr].[geolocation]    Script Date: 10/23/2026 5:00:04 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[geolocation](
	[geolocation_zip_code_prefix] [varchar](10) NULL,
	[geolocation_lat] [decimal](18, 8) NOT NULL,
	[geolocation_lng] [decimal](18, 8) NOT NULL,
	[geolocation_city] [varchar](50) NOT NULL,
	[geolocation_state] [varchar](5) NOT NULL
) ON [PRIMARY]
GO


-- 9. product_category_name_translation (71 rows)
/****** Object:  Table [ctr].[product_category_name_translation]    Script Date: 10/23/2026 5:20:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[product_category_name_translation](
	[product_category_name] [nvarchar](100) NOT NULL,
	[product_category_name_english] [varchar](100) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[product_category_name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



-- 10. data_quality_log (14 rows) - audit table for anomalies we flag, never fake
/****** Object:  Table [ctr].[data_quality_log]    Script Date: 10/23/2026 4:58:51 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [ctr].[data_quality_log](
	[table_name] [varchar](50) NULL,
	[record_id] [varchar](50) NULL,
	[issue_desc] [varchar](200) NULL,
	[logged_at] [datetime] NULL
) ON [PRIMARY]
GO

ALTER TABLE [ctr].[data_quality_log] ADD  DEFAULT (getdate()) FOR [logged_at]
GO
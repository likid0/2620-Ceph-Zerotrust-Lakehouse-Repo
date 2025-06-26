-- 1️⃣ Find any duplicate “Soda” rows
SELECT
  product_id,
  product_name,
  category,
  price,
  quantity,
  COUNT(*) AS occurrences
FROM products_raw
WHERE product_name = 'Soda'
GROUP BY
  product_id,
  product_name,
  category,
  price,
  quantity
HAVING COUNT(*) > 1
;

-- 2️⃣ Delete every “extra” copy, keeping one per (id,name,category,price,quantity)
DELETE FROM products_raw
 WHERE (product_id, product_name, category, price, quantity, timestamp)
   IN (
     SELECT product_id,
            product_name,
            category,
            price,
            quantity,
            timestamp
       FROM (
         SELECT
           product_id,
           product_name,
           category,
           price,
           quantity,
           timestamp,
           row_number() OVER (
             PARTITION BY product_id, product_name, category, price, quantity
             ORDER BY timestamp
           ) AS rn
         FROM products_raw
       ) AS dup
      WHERE dup.rn > 1
   )
;

-- 3️⃣ Verify there are no more duplicates
SELECT
  product_id,
  product_name,
  category,
  price,
  quantity,
  COUNT(*) AS occurrences
FROM products_raw
WHERE product_name = 'Soda'
GROUP BY
  product_id,
  product_name,
  category,
  price,
  quantity
HAVING COUNT(*) > 1
;

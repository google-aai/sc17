WITH all_images_and_labels AS (
  SELECT i.original_url, l.label_name, l.confidence
  FROM `bigquery-public-data.open_images.images` i
  JOIN `bigquery-public-data.open_images.labels` l
  ON i.image_id = l.image_id
)
SELECT original_url, label, RAND() as randnum
FROM
(
  SELECT DISTINCT original_url, 1 as label
  FROM all_images_and_labels
  WHERE confidence = 1
  AND label_name LIKE '/m/01yrx'
  UNION ALL
  (
    SELECT DISTINCT all_images.original_url, 0 as label
    FROM all_images_and_labels all_images
    LEFT JOIN
    (
      SELECT original_url
      FROM all_images_and_labels
      WHERE confidence = 1
      AND NOT (label_name LIKE '/m/01yrx')
    ) not_cat
    ON all_images.original_url = not_cat.original_url
    WHERE not_cat.original_url IS NULL
    LIMIT 40000
  )
)
ORDER BY randnum
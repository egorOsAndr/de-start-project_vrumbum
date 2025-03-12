-- Этап 1. Создание и заполнение БД
CREATE SCHEMA IF NOT EXISTS raw_date;
CREATE SCHEMA IF NOT EXISTS car_shop;


CREATE TABLE IF NOT EXISTS raw_date.sales (
	id INTEGER PRIMARY KEY,
	auto TEXT NOT NULL,
	gasoline_consumption VARCHAR,
	price NUMERIC(8, 2) NOT NULL CHECK(price < 1000000),
	date DATE NOT NULL,
	person_name TEXT NOT NULL,
	phone TEXT NOT NULL,
	discount INT2 NOT NULL,
	brand_origin TEXT
);


CREATE TABLE IF NOT EXISTS car_shop.brands (
    id SERIAL PRIMARY KEY,
    brand_name VARCHAR NOT NULL UNIQUE, /* Название бренда может содержать цифры */
    origin VARCHAR NOT NULL /* Страна происхождения бренда в ней неучаствуют цифры */
);

CREATE TABLE IF NOT EXISTS car_shop.models (
    id SERIAL PRIMARY KEY,
    brand_id INTEGER REFERENCES car_shop.brands (id) ON DELETE CASCADE,
    name_model VARCHAR NOT NULL UNIQUE /* Название модели может содержать цифры */
);

CREATE TABLE IF NOT EXISTS car_shop.cars (
    id SERIAL PRIMARY KEY,
    model_id INTEGER REFERENCES car_shop.models (id) ON DELETE CASCADE,
    price NUMERIC(9,2) NOT NULL CHECK (price < 1000000), /* не может быть больше семизначного числа */
    gasoline_consumption NUMERIC(5,2) CHECK (gasoline_consumption < 100) /* не может быть больше трех значного числа */
);

CREATE TABLE IF NOT EXISTS car_shop.colors (
    id SERIAL PRIMARY KEY,
    color_name TEXT NOT NULL UNIQUE /* цвет может содержать цифры и состоять из нескольких цветов */
);

CREATE TABLE IF NOT EXISTS car_shop.cars_colors (
	id SERIAL PRIMARY KEY,
    car_id INTEGER REFERENCES car_shop.cars (id) ON DELETE CASCADE,
    color_id INTEGER REFERENCES car_shop.colors (id) ON DELETE CASCADE
);


CREATE TABLE IF NOT EXISTS car_shop.clients (
    id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL, /* Имя может быть составным поэтому может быть довольно большим */
    last_name TEXT NOT NULL, /* Фамилия может быть составным поэтому может быть довольно большим */
 	UNIQUE (first_name, last_name)
);



-- таблица sales будет таблицей фактов, которая будет хранить данные о сделках 
CREATE TABLE IF NOT EXISTS car_shop.sales (
    id SERIAL PRIMARY KEY,
    car_id INTEGER REFERENCES car_shop.cars (id) ON DELETE CASCADE,
    client_id INTEGER REFERENCES car_shop.clients (id) ON DELETE CASCADE,
    date DATE NOT NULL /* сырые данные поступают в типе даты */
);


CREATE TABLE IF NOT EXISTS car_shop.phone_numbers (
    id SERIAL PRIMARY KEY,
    client_id INTEGER REFERENCES car_shop.clients (id) ON DELETE CASCADE,
    phone TEXT NOT NULL UNIQUE /* телефон без добавочного */
);

CREATE TABLE car_shop.phone_extensions (
    id SERIAL PRIMARY KEY,
    phone_id INTEGER REFERENCES car_shop.phone_numbers(id) ON DELETE CASCADE UNIQUE,
    extension VARCHAR NOT NULL /* добавочный номер */
);

CREATE TABLE IF NOT EXISTS car_shop.discounts (
    id SERIAL PRIMARY KEY,
    client_id INTEGER REFERENCES car_shop.clients (id) ON DELETE CASCADE UNIQUE,
    discount INT2 NOT NULL CHECK (discount BETWEEN 0 AND 100) /* скидка не может превышать 100 */
);


INSERT INTO car_shop.brands (
	brand_name,
	origin
)
SELECT 
	DISTINCT ON (SPLIT_PART(auto, ' ', 1)) SPLIT_PART(auto, ' ', 1) AS brand_name,
	brand_origin
FROM
	raw_date.sales;
	

INSERT INTO car_shop.models (
	brand_id,
	name_model
)
SELECT
	DISTINCT
	b.id,
	TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, 
		SPLIT_PART(SPLIT_PART(auto, ', ', 1),
		' ', 2))), ', ', 1)) AS name_model
FROM
	raw_date.sales AS a
	-- использовал RIGHT, важно так как нужны все модели у которых есть запись о бренде
	RIGHT JOIN car_shop.brands AS b ON SPLIT_PART(a.auto, ' ', 1) = b.brand_name;


INSERT INTO car_shop.cars (
	model_id,
	price,
	gasoline_consumption
)
SELECT
	DISTINCT
	m.id,
	s.price,
	COALESCE(NULLIF(NULLIF(s.gasoline_consumption, 'null'), '')::NUMERIC(5, 2), NUll) AS gasoline_consumption
FROM
	raw_date.sales AS s
	-- выбрал тип соединения rigth так как нам важны все записи у которых есть
	-- запись в таблице models
	RIGHT JOIN car_shop.models AS m 
	ON TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, 
		SPLIT_PART(SPLIT_PART(auto, ', ', 1),
		' ', 2))), ', ', 1)) = m.name_model;


INSERT INTO car_shop.colors (
	color_name
)
SELECT
	DISTINCT TRIM(SUBSTR(auto, STRPOS(auto, ',') + 2)) AS color_name
FROM
	raw_date.sales;

INSERT INTO car_shop.cars_colors (
    car_id,
    color_id
)
SELECT
	DISTINCT
	c.id AS car_id,
	col.id AS color_id
FROM raw_date.sales AS s 
	RIGHT JOIN car_shop.models AS m ON m.name_model = 
		TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, 
		SPLIT_PART(SPLIT_PART(auto, ', ', 1),
		' ', 2))), ', ', 1))
	INNER JOIN car_shop.cars AS c ON c.model_id = m.id
		AND c.price = s.price
	RIGHT JOIN car_shop.colors AS col
		ON col.color_name = TRIM(SUBSTR(auto, STRPOS(auto, ',') + 2));

		
INSERT INTO car_shop.clients (
	first_name,
	last_name
)
SELECT
	DISTINCT
	TRIM(SPLIT_PART(person_name, ' ', 1)) AS first_name,
	TRIM(SPLIT_PART(person_name, ' ', 2)) AS last_name
FROM 
	raw_date.sales;


INSERT INTO car_shop.phone_numbers (
	client_id,
	phone
)
SELECT DISTINCT
	c.id,
	TRIM(REGEXP_REPLACE(SPLIT_PART(s.phone, 'x', 1), '[()-]', '', 'g')) AS phone
FROM car_shop.clients AS c 
	LEFT JOIN raw_date.sales AS s ON c.first_name = TRIM(SPLIT_PART(s.person_name, ' ', 1))
	AND c.last_name = TRIM(SPLIT_PART(person_name, ' ', 2));

	
INSERT INTO car_shop.phone_extensions (
	phone_id,
	extension
	)
SELECT
	DISTINCT ON
	(TRIM(pn.id,
	NULLIF(SPLIT_PART(s.phone, 'x', 2), '')))
	pn.id,
	TRIM(NULLIF(SPLIT_PART(s.phone, 'x', 2), '')) AS extension
FROM car_shop.phone_numbers AS pn
	LEFT JOIN raw_date.sales AS s ON pn.phone = TRIM(REGEXP_REPLACE(SPLIT_PART(s.phone, 'x', 1), '[()-]', '', 'g'))
WHERE
	NULLIF(SPLIT_PART(s.phone, 'x', 2), '') IS NOT NULL;


INSERT INTO car_shop.discounts (
	client_id,
	discount
)
SELECT
	id,
	discount
FROM
	(
	SELECT
		c.id,
		s.discount,
		s.date,
		-- применил оконную функцию для того чтобы выбрать самые последние скидки пользователей
		ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY s.date DESC) AS rn
	FROM car_shop.clients c
		LEFT JOIN raw_date.sales s ON c.first_name = TRIM(SPLIT_PART(s.person_name, ' ', 1))
		AND c.last_name = TRIM(SPLIT_PART(person_name, ' ', 2))
	WHERE s.discount != 0
	) AS tb
WHERE rn = 1;


INSERT INTO car_shop.sales (
	car_id,
	client_id,
	date
)
SELECT
	DISTINCT ON (car.id)
	car.id,
	c.id,
	s.date
FROM raw_date.sales s 
	RIGHT JOIN car_shop.models m ON m.name_model = 
		TRIM(SPLIT_PART(SUBSTR(auto, STRPOS(auto, 
		SPLIT_PART(SPLIT_PART(auto, ', ', 1),
		' ', 2))), ', ', 1))
	RIGHT JOIN car_shop.cars car
		ON car.price = s.price
	RIGHT JOIN car_shop.clients c ON c.first_name = TRIM(SPLIT_PART(s.person_name, ' ', 1))
	AND c.last_name = TRIM(SPLIT_PART(person_name, ' ', 2));



-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.

SELECT 
	(
	SELECT
		COUNT(model_id)
	FROM
		car_shop.cars
	WHERE
		gasoline_consumption IS NULL
	)::NUMERIC / COUNT(model_id) AS nulls_percentage_gasoline_consumption
FROM car_shop.cars;

---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.

SELECT 
	b.brand_name,
	EXTRACT(YEAR FROM s.date) AS year,
	ROUND(AVG(c.price), 2) AS avg_price
FROM car_shop.cars AS c
	JOIN car_shop.models AS m ON c.model_id = m.id
	JOIN car_shop.brands AS b ON m.brand_id = b.id
	JOIN car_shop.sales AS s ON s.car_id = c.id
	JOIN car_shop.clients AS cl ON s.client_id = cl.id
	JOIN car_shop.discounts AS d ON cl.id = d.client_id
GROUP BY
	EXTRACT(YEAR FROM s.date),
	b.brand_name
ORDER BY
	b.brand_name,
	EXTRACT(YEAR FROM s.date);

---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.
SELECT
	mth,
	2022 AS year,
	ROUND(AVG(c.price), 2) AS price_avg
FROM GENERATE_SERIES(1, 12) AS mth
LEFT JOIN car_shop.sales AS s ON EXTRACT(YEAR FROM s.date) = 2022 
AND EXTRACT(MONTH FROM s.date) = mth
LEFT JOIN car_shop.cars AS c ON c.id = s.car_id
LEFT JOIN car_shop.clients AS cl ON cl.id = s.client_id
LEFT JOIN car_shop.discounts AS d ON d.client_id = cl.id
GROUP BY
	mth
ORDER BY
	mth;


---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.

SELECT
	cl.first_name || ' ' || cl.last_name AS person,
	STRING_AGG(b.brand_name || ' ' || m.name_model, ', ') AS cars
FROM car_shop.sales AS s
	JOIN car_shop.cars AS c ON s.car_id = c.id
	JOIN car_shop.models AS m ON c.model_id = m.id
	JOIN car_shop.brands AS b ON b.id = m.brand_id
	JOIN car_shop.clients AS cl ON s.client_id = cl.id
GROUP BY person;



---- Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля с разбивкой по
---- стране без учёта скидки. Цена в колонке price дана с учётом скидки.

SELECT
	b.origin AS brand_origin,
	MAX(c.price / (1 - d.discount / 100)) AS price_max,
	MIN(c.price / (1 - d.discount / 100)) AS price_min
FROM
	car_shop.cars AS c
	JOIN car_shop.models AS m ON c.model_id = m.id
	JOIN car_shop.brands AS b ON m.brand_id = b.id
	JOIN car_shop.sales AS s ON s.car_id = c.id
	JOIN car_shop.clients AS cl ON s.client_id = cl.id
	JOIN car_shop.discounts AS d ON d.client_id = cl.id
WHERE b.origin IS NOT NULL
GROUP BY
	brand_origin

  
---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США.


SELECT
	COUNT(DISTINCT cl.id)
FROM car_shop.sales s 
	JOIN car_shop.clients cl ON s.client_id = cl.id
	JOIN car_shop.phone_numbers pn ON pn.client_id = cl.id
WHERE pn.phone ~ '^\+1.*'



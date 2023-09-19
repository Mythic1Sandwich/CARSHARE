--
-- PostgreSQL database dump
--

-- Dumped from database version 15.1
-- Dumped by pg_dump version 15.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: add_fine_to_bill(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_fine_to_bill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
UPDATE inuse SET bill = bill + new.cost WHERE client_id = new.client_id; RETURN NEW; END; $$;


ALTER FUNCTION public.add_fine_to_bill() OWNER TO postgres;

--
-- Name: adjust_car_amount(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.adjust_car_amount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE cars SET amount = amount - 1
        WHERE cars.car_id = NEW.car_id;
    END IF;
    
    IF TG_OP = 'UPDATE' THEN
        IF NEW.return_condition > 1 THEN
            UPDATE cars SET amount = amount + 1
            WHERE cars.car_id = OLD.car_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.adjust_car_amount() OWNER TO postgres;

--
-- Name: amount(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.amount() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
if tg_op = 'INSERT' then
         update cars set amount=amount-1
         where cars.car_id=new.car_id;
	     return new;
       end if;
if tg_op = 'UPDATE' then 
       if new.return_condition=4 then
	   insert into fines values(old.car_id,old.client_id,'Незначительные повреждения',(select cars.car_cost*0.2 from cars where cars.car_id=old.car_id));
	   end if;
	   if new.return_condition=3 then
	   insert into fines values(old.car_id,old.client_id,'Повреждения',(select cars.car_cost*0.4 from cars where cars.car_id=old.car_id));
	   end if;
	    if new.return_condition=2 then
	   insert into fines values(old.car_id,old.client_id,'Значительные повреждения',(select cars.car_cost*0.8 from cars where cars.car_id=old.car_id));
	   end if;
	    if new.return_condition=1 then
	   insert into fines values(old.car_id,old.client_id,'Вывод средства из эксплуатации',(select cars.car_cost*1.3 from cars where cars.car_id=old.car_id));
	    update cars set amount=amount-1
		    where cars.car_id=old.car_id;
	   end if;
       if new.real_return IS NOT NULL and DATE_PART('Day', new.real_return::TIMESTAMP - old.return_date::TIMESTAMP)>0 then
	       update cars set amount=amount+1
		    where cars.car_id=old.car_id;
           insert into fines values(old.car_id,old.client_id,'Просрочка даты возврата',DATE_PART('Day', new.real_return::TIMESTAMP - old.return_date::TIMESTAMP)*10000);
       end if;
       if DATE_PART('Day', new.real_return::TIMESTAMP - old.return_date::TIMESTAMP)=0 then
	      
          update cars set amount=amount+1
          where cars.car_id=old.car_id;
	   end if;
	   return old;


end if;
end;
$$;


ALTER FUNCTION public.amount() OWNER TO postgres;

--
-- Name: avg_bill_per_client(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.avg_bill_per_client() RETURNS TABLE(client_id integer, first_name character varying, last_name character varying, avg_bill numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
    SELECT c.client_id, c.first_name, c.last_name, CAST(AVG(i.bill) AS numeric(10,2)) as avg_bill
    FROM clients c
    JOIN inuse i ON c.client_id = i.client_id
    GROUP BY c.client_id
    ORDER BY avg_bill DESC;
END;
$$;


ALTER FUNCTION public.avg_bill_per_client() OWNER TO postgres;

--
-- Name: calculate_avg_time_between_orders(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_avg_time_between_orders(client_id1 integer) RETURNS interval
    LANGUAGE plpgsql
    AS $$
DECLARE
  prev_order_date DATE;
  curr_order_date DATE;
  avg_interval INTERVAL;
  total_interval INTERVAL := INTERVAL '0';
  total_count INT := 0;
BEGIN
  SELECT MIN(give_date) INTO prev_order_date
  FROM inuse
  WHERE inuse.client_id = client_id1;

  FOR curr_order_date IN (
    SELECT give_date
    FROM inuse
    WHERE inuse.client_id = client_id1 AND give_date > prev_order_date
    ORDER BY give_date ASC
  ) LOOP
    IF prev_order_date IS NOT NULL THEN
      total_interval := total_interval + make_interval(days => curr_order_date - prev_order_date); -- изменение здесь
      total_count := total_count + 1;
    END IF;
    prev_order_date := curr_order_date;
  END LOOP;

  IF total_count > 0 THEN
    avg_interval := total_interval / total_count;
  ELSE
    avg_interval := INTERVAL '0';
  END IF;

  RETURN avg_interval;
END;
$$;


ALTER FUNCTION public.calculate_avg_time_between_orders(client_id1 integer) OWNER TO postgres;

--
-- Name: calculate_months_to_pay(numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_months_to_pay(monthly_payment numeric) RETURNS TABLE(fine_id integer, months_to_pay integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
    SELECT fines.fine_id, CEIL(cost / monthly_payment)::integer AS months_to_pay
    FROM fines;
END;
$$;


ALTER FUNCTION public.calculate_months_to_pay(monthly_payment numeric) OWNER TO postgres;

--
-- Name: change_bill(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.change_bill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Вставляем значение в таблицу inuse
        INSERT INTO inuse (car_id, give_date, return_date, share_cost, bill)
        VALUES (NEW.car_id, NEW.give_date, NEW.return_date, NEW.share_cost, 0);

        -- Проверяем, является ли клиент постоянным
        IF (SELECT discount FROM val_clients WHERE client_id = NEW.client_id) IS NOT NULL THEN
            RAISE NOTICE 'updating inuse, bill: %', NEW.bill;
            -- Обновляем значение поля discount_bill, если клиент постоянный
            UPDATE inuse SET discount_bill = NEW.bill * (SELECT discount FROM val_clients WHERE client_id = NEW.client_id) WHERE car_id = NEW.car_id;
            RAISE NOTICE 'updated inuse, discount_bill: %', NEW.discount_bill;
        END IF;

        -- Обновляем значение поля bill на основе условий, указанных в задании
        IF (SELECT extract(year FROM release_date) FROM cars WHERE cars.car_id = NEW.car_id) BETWEEN 2000 AND 2005 THEN 
            UPDATE inuse SET bill = (SELECT share_cost * 1.5 * DATE_PART('day', return_date::TIMESTAMP - give_date::TIMESTAMP) FROM inuse WHERE car_id = NEW.car_id) WHERE car_id = NEW.car_id;
        ELSIF (SELECT extract(year FROM release_date) FROM cars WHERE cars.car_id = NEW.car_id) BETWEEN 2005 AND 2015 THEN 
            UPDATE inuse SET bill = (SELECT share_cost * 2.5 * DATE_PART('day', return_date::TIMESTAMP - give_date::TIMESTAMP) FROM inuse WHERE car_id = NEW.car_id) WHERE car_id = NEW.car_id;
        ELSIF (SELECT extract(year FROM release_date) FROM cars WHERE cars.car_id = NEW.car_id) BETWEEN 2015 AND 2023 THEN 
            UPDATE inuse SET bill = (SELECT share_cost * 3.5 * DATE_PART('day', return_date::TIMESTAMP - give_date::TIMESTAMP) FROM inuse WHERE car_id = NEW.car_id) WHERE car_id = NEW.car_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.change_bill() OWNER TO postgres;

--
-- Name: check_blacklist(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_blacklist() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT'  THEN
        IF (SELECT client_id FROM fines WHERE client_id = NEW.client_id AND reason = 'Вывод средства из эксплуатации')=new.client_id THEN
            RAISE EXCEPTION 'Вы находитесь в черном списке.';
        END IF;
   
         
    RETURN NEW;
	END IF;
END;
$$;


ALTER FUNCTION public.check_blacklist() OWNER TO postgres;

--
-- Name: check_blacklist_on_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_blacklist_on_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.return_condition = 1 AND NEW.client_id = OLD.client_id THEN
            RAISE EXCEPTION 'Вы находитесь в черном списке.';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' OR TG_OP = 'INSERT' THEN
        IF EXISTS(SELECT 1 FROM inuse WHERE client_id = NEW.client_id AND return_condition = 1) THEN
            RAISE EXCEPTION 'Клиент находится в черном списке.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_blacklist_on_order() OWNER TO postgres;

--
-- Name: check_value(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_value() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    order_count INTEGER;
BEGIN
    -- Подсчитываем количество заказов текущего клиента в каждом году
    SELECT COUNT(*) INTO order_count
    FROM inuse
    WHERE inuse.client_id = NEW.client_id
    GROUP BY EXTRACT(YEAR FROM give_date)
    HAVING COUNT(*) = 3 OR COUNT(*) = 6 OR COUNT(*) = 10;

    -- Если количество заказов >= 3 в любом году, и клиент не находится в таблице fines,
    -- то проверяем, есть ли уже такой клиент в списке постоянных
    IF (order_count >= 3 OR order_count >= 6 OR order_count >= 10) AND NOT EXISTS (SELECT 1 FROM fines WHERE fines.client_id = NEW.client_id) THEN
        IF EXISTS (SELECT 1 FROM val_clients WHERE val_clients.client_id = NEW.client_id) THEN
            -- Если клиент уже есть в списке постоянных, то обновляем коэффициент скидки
            UPDATE val_clients SET discount = CASE 
                                                WHEN order_count >= 3 AND discount = 1.0 THEN 0.95 
                                                WHEN order_count >= 6 THEN 0.9
                                                WHEN order_count >= 10 THEN 0.8
                                                ELSE discount
                                            END
            WHERE client_id = NEW.client_id;
        ELSE
            -- Если клиента еще нет в списке постоянных, то добавляем его туда с коэффициентом скидки 0.95
            INSERT INTO val_clients (client_id, discount) 
            VALUES (NEW.client_id, 0.95);
        END IF;
    END IF;


    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_value() OWNER TO postgres;

--
-- Name: low_expense_clients(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.low_expense_clients(n integer) RETURNS TABLE(rank integer, client_id integer, first_name character varying, last_name character varying, total_bill numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
    SELECT ROW_NUMBER() OVER (ORDER BY sum(i.bill) ASC)::int AS rank, c.client_id, c.first_name, c.last_name, CAST(sum(i.bill) AS numeric(10,2)) AS total_bill
    FROM clients c
    JOIN inuse i ON c.client_id = i.client_id
    GROUP BY c.client_id
    ORDER BY total_bill ASC
    LIMIT n;
END;
$$;


ALTER FUNCTION public.low_expense_clients(n integer) OWNER TO postgres;

--
-- Name: low_expense_clients(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.low_expense_clients(n bigint) RETURNS TABLE(rank integer, client_id integer, first_name character varying, last_name character varying, total_bill numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
    SELECT ROW_NUMBER() OVER (ORDER BY sum(i.bill) ASC) AS rank, c.client_id, c.first_name, c.last_name, sum(i.bill) AS total_bill
    FROM clients c
    JOIN inuse i ON c.client_id = i.client_id
    GROUP BY c.client_id
    ORDER BY total_bill ASC
    LIMIT n;
END;
$$;


ALTER FUNCTION public.low_expense_clients(n bigint) OWNER TO postgres;

--
-- Name: proc(integer, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.proc(y1 integer, y2 integer, last_name text) RETURNS double precision
    LANGUAGE sql
    AS $$
 select abs((yr(y2,last_name) - yr(y1,last_name))/yr(y1,last_name)*100)
$$;


ALTER FUNCTION public.proc(y1 integer, y2 integer, last_name text) OWNER TO postgres;

--
-- Name: process_fines(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.process_fines() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.return_condition = 4 THEN
	       INSERT INTO fines VALUES (OLD.car_id, OLD.client_id, 'Незначительные повреждения', (SELECT cars.car_cost * 0.2 FROM cars WHERE cars.car_id = OLD.car_id),(select count(*)+1 from fines),old.order_id);
	    END IF;

	    IF NEW.return_condition = 3 THEN
	       INSERT INTO fines VALUES (OLD.car_id, OLD.client_id, 'Повреждения', (SELECT cars.car_cost * 0.4 FROM cars WHERE cars.car_id = OLD.car_id),(select count(*)+1 from fines),old.order_id);
	    END IF;

	    IF NEW.return_condition = 2 THEN
	       INSERT INTO fines VALUES (OLD.car_id, OLD.client_id, 'Значительные повреждения', (SELECT cars.car_cost * 0.8 FROM cars WHERE cars.car_id = OLD.car_id),(select count(*)+1 from fines),old.order_id);
	    END IF;

	    IF NEW.return_condition = 1 THEN
	       INSERT INTO fines VALUES (OLD.car_id, OLD.client_id, 'Вывод средства из эксплуатации', (SELECT cars.car_cost * 1.3 FROM cars WHERE cars.car_id = OLD.car_id),(select count(*)+1 from fines),old.order_id);
	    END IF;

	    IF DATE_PART('Day', NEW.real_return::TIMESTAMP - OLD.return_date::TIMESTAMP) > 0 THEN
           INSERT INTO fines VALUES (OLD.car_id, OLD.client_id, 'Просрочка даты возврата', DATE_PART('DAY', NEW.real_return::TIMESTAMP - OLD.return_date::TIMESTAMP) * 60000,(select count(*)+1 from fines),old.order_id);
	    END IF;

	END IF;
    
    RETURN OLD;
END;

$$;


ALTER FUNCTION public.process_fines() OWNER TO postgres;

--
-- Name: trigger_bill(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_bill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
if tg_op='INSERT' then
if (select client_id from val_clients where client_id=new.client_id)=new.client_id then
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2000 and 2005 then 
update inuse set bill = (select share_cost * 1.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id)*(select discount from val_clients where client_id=new.client_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id) between 2005 and 2015 then 
update inuse set bill = (select share_cost * 2.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id)*(select discount from val_clients where client_id=new.client_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2015 and 2023 then 
update inuse set bill = (select share_cost * 3.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id)*(select discount from val_clients where client_id=new.client_id) where order_id=new.order_id;
end if;

else
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2000 and 2005 then 
update inuse set bill = (select share_cost * 1.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id) between 2005 and 2015 then 
update inuse set bill = (select share_cost * 2.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id) where order_id=new.order_id;
end if;
if (select extract(year from release_date) from cars where cars.car_id=new.car_id)  between 2015 and 2023 then 
update inuse set bill = (select share_cost * 3.5*DATE_PART('Day', return_date::TIMESTAMP - give_date::TIMESTAMP ) from cars where cars.car_id=new.car_id) where order_id=new.order_id;
end if;
end if;
end if;
return new;
end;
$$;


ALTER FUNCTION public.trigger_bill() OWNER TO postgres;

--
-- Name: update_discount_bill(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_discount_bill() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM val_clients WHERE client_id = NEW.client_id AND discount IS NOT NULL) THEN
    UPDATE inuse SET discount_bill = NEW.bill * (SELECT discount FROM val_clients WHERE client_id = NEW.client_id) WHERE client_id = NEW.client_id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_discount_bill() OWNER TO postgres;

--
-- Name: update_inuse(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_inuse() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE 
  client_discount NUMERIC;
BEGIN
  SELECT discount INTO client_discount FROM val_clients WHERE client_id = NEW.client_id AND discount IS NOT NULL;
  IF client_discount IS NOT NULL THEN
    NEW.discount_bill := NEW.bill * client_discount;
    NEW.bill := NEW.discount_bill;
  ELSE
    NEW.discount_bill := 0;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_inuse() OWNER TO postgres;

--
-- Name: yr(integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.yr(yr integer, ln text) RETURNS double precision
    LANGUAGE sql
    AS $$
select sum(inuse.bill) from inuse join clients on clients.client_id=inuse.client_id where extract(year from give_date)=yr and clients.last_name=ln
$$;


ALTER FUNCTION public.yr(yr integer, ln text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cars; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cars (
    car_id integer NOT NULL,
    mark character varying(255),
    car_cost integer,
    share_cost integer,
    type character varying(255),
    release_date date,
    fullname character varying(255),
    amount integer,
    CONSTRAINT cars_amount_check CHECK ((amount >= 0))
);


ALTER TABLE public.cars OWNER TO postgres;

--
-- Name: clients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clients (
    client_id integer NOT NULL,
    first_name character varying(255),
    last_name character varying(255),
    surname character varying(255),
    address character varying(255),
    phone_num character varying(255)
);


ALTER TABLE public.clients OWNER TO postgres;

--
-- Name: fines; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fines (
    car_id integer,
    client_id integer,
    reason character varying(255),
    cost integer,
    fine_id integer NOT NULL,
    order_id integer
);


ALTER TABLE public.fines OWNER TO postgres;

--
-- Name: inuse; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.inuse (
    car_id integer,
    client_id integer,
    give_date date,
    return_date date,
    bill double precision,
    order_id integer NOT NULL,
    return_condition integer,
    real_return date,
    CONSTRAINT inuse_return_condition_check CHECK ((return_condition <= 5)),
    CONSTRAINT inuse_return_condition_check1 CHECK (((return_condition > 0) AND (return_condition <= 5)))
);


ALTER TABLE public.inuse OWNER TO postgres;

--
-- Name: val_clients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.val_clients (
    client_id integer NOT NULL,
    discount double precision
);


ALTER TABLE public.val_clients OWNER TO postgres;

--
-- Data for Name: cars; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cars (car_id, mark, car_cost, share_cost, type, release_date, fullname, amount) FROM stdin;
3	Toyota	2800000	17500	универсал	2021-05-17	TOYOTA YARIS CROSS	14
6	FORD	2900000	21500	хэтчбек	2016-07-09	FORD KA+	32
1	Toyota	2500000	14500	купе	2021-11-17	TOYOTA GR 86	23
2	Toyota	1700000	11500	универсал	2015-07-16	TOYOTA FORTUNER	20
8	PORSCHE	5600000	43000	универсал	2022-03-09	PORSCHE TAYCAN CROSS TURISMO	15
5	FORD	2900000	21500	универсал	2019-01-09	FORD EXPLORER	20
7	MERCEDES-BENZ	4900000	45000	универсал	2021-07-09	MERCEDES-BENZ GLS MAYBACH	19
4	FORD	1700000	10500	седан	2010-01-17	FORD TAURUS	21
\.


--
-- Data for Name: clients; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clients (client_id, first_name, last_name, surname, address, phone_num) FROM stdin;
1	Кирилл	Никонов	Игоревич	ул.Часовая 13	89178549933
2	Андрей	Никонов	Игоревич	ул.Семеновская 43	89278949533
3	Сергей	Алексеев	Семенович	ул.Спартаковская 1	89296494477
4	Валерия	Вишневская	Олеговна	ул.Песчаная 3с3	89510648232
5	Олеся	Васильева	Михайловна	ул.Соколова 5	89138420055
6	Виталий	Михайлов	Тимурович	ул.Тимирязевская 12	89192731363
\.


--
-- Data for Name: fines; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fines (car_id, client_id, reason, cost, fine_id, order_id) FROM stdin;
8	5	Просрочка даты возврата	43860000	5	17
8	5	Вывод средства из эксплуатации	7280000	6	18
7	2	Незначительные повреждения	980000	1	5
4	2	Незначительные повреждения	340000	2	6
7	6	Вывод средства из эксплуатации	6370000	4	13
4	3	Просрочка даты возврата	120000	3	11
\.


--
-- Data for Name: inuse; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.inuse (car_id, client_id, give_date, return_date, bill, order_id, return_condition, real_return) FROM stdin;
1	5	2022-09-18	2022-09-20	101500	15	5	2021-09-20
2	5	2022-09-25	2022-09-28	114712.5	16	5	2021-09-28
1	1	2021-07-25	2021-07-27	101500	1	5	2021-07-27
2	1	2021-07-28	2021-07-29	40250	2	5	2021-07-29
5	1	2021-09-01	2021-09-05	285950	3	5	2021-09-05
3	2	2019-05-01	2019-05-02	61250	4	5	2019-05-02
7	2	2019-06-01	2019-06-07	945000	5	4	2019-06-07
4	2	2022-02-01	2022-02-05	105000	6	4	2022-02-05
7	1	2021-09-06	2021-09-08	299250	7	5	2021-09-08
1	1	2021-09-15	2021-09-17	96425	8	5	2021-09-17
3	1	2021-09-21	2021-09-24	165375	9	5	2021-09-24
1	1	2021-10-28	2021-10-29	45675	10	5	2021-10-29
4	3	2021-10-28	2021-10-29	26250	11	5	2021-10-29
6	4	2021-10-17	2021-10-29	903000	12	5	2021-10-29
7	6	2021-10-21	2021-10-22	157500	13	1	2021-10-22
6	5	2022-09-14	2022-09-16	150500	14	5	2022-09-16
8	5	2019-07-01	2019-07-05	571900	17	5	2021-07-05
8	5	2019-07-05	2019-07-06	142975	18	1	2019-07-06
\.


--
-- Data for Name: val_clients; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.val_clients (client_id, discount) FROM stdin;
1	0.9
5	0.95
\.


--
-- Name: cars cars_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cars
    ADD CONSTRAINT cars_pkey PRIMARY KEY (car_id);


--
-- Name: val_clients client_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.val_clients
    ADD CONSTRAINT client_id PRIMARY KEY (client_id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (client_id);


--
-- Name: fines fines_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fines
    ADD CONSTRAINT fines_pkey PRIMARY KEY (fine_id);


--
-- Name: inuse inuse_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inuse
    ADD CONSTRAINT inuse_pkey PRIMARY KEY (order_id);


--
-- Name: fines add_fine_to_bill_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER add_fine_to_bill_trigger AFTER INSERT ON public.fines FOR EACH ROW EXECUTE FUNCTION public.add_fine_to_bill();

ALTER TABLE public.fines DISABLE TRIGGER add_fine_to_bill_trigger;


--
-- Name: inuse adjust_car_amount_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER adjust_car_amount_trigger AFTER INSERT OR UPDATE ON public.inuse FOR EACH ROW EXECUTE FUNCTION public.adjust_car_amount();


--
-- Name: inuse amo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER amo AFTER INSERT OR UPDATE ON public.inuse FOR EACH ROW EXECUTE FUNCTION public.amount();

ALTER TABLE public.inuse DISABLE TRIGGER amo;


--
-- Name: inuse bill; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER bill AFTER INSERT ON public.inuse FOR EACH ROW EXECUTE FUNCTION public.trigger_bill();


--
-- Name: inuse check_blacklist_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_blacklist_trigger BEFORE INSERT ON public.inuse FOR EACH ROW EXECUTE FUNCTION public.check_blacklist();


--
-- Name: inuse check_discount; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_discount AFTER INSERT ON public.inuse FOR EACH ROW EXECUTE FUNCTION public.check_value();


--
-- Name: inuse process_fines_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER process_fines_trigger AFTER UPDATE ON public.inuse FOR EACH ROW EXECUTE FUNCTION public.process_fines();


--
-- Name: inuse trigg; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigg AFTER INSERT ON public.inuse FOR EACH ROW EXECUTE FUNCTION public.trigger_bill();


--
-- Name: fines fines_car_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fines
    ADD CONSTRAINT fines_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(car_id);


--
-- Name: fines fines_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fines
    ADD CONSTRAINT fines_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(client_id);


--
-- Name: inuse inuse_car_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inuse
    ADD CONSTRAINT inuse_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(car_id);


--
-- Name: inuse inuse_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inuse
    ADD CONSTRAINT inuse_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(client_id);


--
-- Name: val_clients val_clients_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.val_clients
    ADD CONSTRAINT val_clients_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(client_id);


--
-- PostgreSQL database dump complete
--


CREATE TABLE blog2 (
    id integer NOT NULL,
    col1 character varying(30),
    col2 character varying,
    col3 integer DEFAULT 5 NOT NULL,
    col4 numeric(16,4),
    col5 timestamp without time zone
);
CREATE SEQUENCE blog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE blog_id_seq OWNED BY blog2.id;
ALTER TABLE ONLY blog2 ALTER COLUMN id SET DEFAULT nextval('blog_id_seq'::regclass);
ALTER TABLE ONLY blog2
    ADD CONSTRAINT blog_pkey PRIMARY KEY (id);

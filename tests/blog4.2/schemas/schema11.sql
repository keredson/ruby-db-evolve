CREATE TABLE blog1 (
    id integer NOT NULL,
    col1 character varying
);
CREATE SEQUENCE blog1_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE blog1_id_seq OWNED BY blog1.id;
CREATE TABLE blog2 (
    id integer NOT NULL,
    col1 character varying
);
CREATE TABLE blog3 (
    id integer NOT NULL,
    col1 character varying
);
CREATE SEQUENCE blog3_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE blog3_id_seq OWNED BY blog3.id;
CREATE TABLE blog4 (
    id integer NOT NULL,
    col1 character varying
);
CREATE SEQUENCE blog4_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE blog4_id_seq OWNED BY blog4.id;
CREATE SEQUENCE blog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE blog_id_seq OWNED BY blog2.id;
ALTER TABLE ONLY blog1 ALTER COLUMN id SET DEFAULT nextval('blog1_id_seq'::regclass);
ALTER TABLE ONLY blog2 ALTER COLUMN id SET DEFAULT nextval('blog_id_seq'::regclass);
ALTER TABLE ONLY blog3 ALTER COLUMN id SET DEFAULT nextval('blog3_id_seq'::regclass);
ALTER TABLE ONLY blog4 ALTER COLUMN id SET DEFAULT nextval('blog4_id_seq'::regclass);
ALTER TABLE ONLY blog1
    ADD CONSTRAINT blog1_pkey PRIMARY KEY (id);
ALTER TABLE ONLY blog3
    ADD CONSTRAINT blog3_pkey PRIMARY KEY (id);
ALTER TABLE ONLY blog4
    ADD CONSTRAINT blog4_pkey PRIMARY KEY (id);
ALTER TABLE ONLY blog2
    ADD CONSTRAINT blog_pkey PRIMARY KEY (id);
REVOKE ALL ON TABLE blog1 FROM PUBLIC;
GRANT SELECT,INSERT,DELETE,TRIGGER,UPDATE ON TABLE blog1 TO db_evolve_test;
GRANT INSERT,UPDATE ON TABLE blog1 TO db_evolve_test2;
REVOKE ALL ON TABLE blog2 FROM PUBLIC;
GRANT INSERT,DELETE ON TABLE blog2 TO db_evolve_test;
GRANT UPDATE ON TABLE blog2 TO db_evolve_test2;
REVOKE ALL ON TABLE blog3 FROM PUBLIC;
GRANT SELECT,INSERT,UPDATE ON TABLE blog3 TO db_evolve_test;
GRANT SELECT,INSERT,UPDATE ON TABLE blog3 TO db_evolve_test2;
REVOKE ALL ON TABLE blog4 FROM PUBLIC;
GRANT SELECT,INSERT,DELETE ON TABLE blog4 TO db_evolve_test;
GRANT INSERT,UPDATE ON TABLE blog4 TO db_evolve_test2;

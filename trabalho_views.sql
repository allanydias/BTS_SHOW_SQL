SET search_path TO views_simples_lento;

CREATE TABLE shows (
    id_show         SERIAL          PRIMARY KEY,
    nome_show       VARCHAR(150)    NOT NULL,
    cidade_show     VARCHAR(100)    NOT NULL,
    data_show       TIMESTAMP       NOT NULL,
    local_show      VARCHAR(200)    NOT NULL
);
 
-- Cada show tem vários setores (Pista, Camarote, etc.)
CREATE TABLE setores (
    id_setor            SERIAL          PRIMARY KEY,
    id_show             INT             NOT NULL,
    nome_setor          VARCHAR(80)     NOT NULL,
    capacidade_setor    INT             NOT NULL,
    preco_setor         NUMERIC(10,2)   NOT NULL,
    FOREIGN KEY (id_show) REFERENCES shows(id_show)
);
 
CREATE TABLE clientes (
    id_cliente          SERIAL          PRIMARY KEY,
    nome_completo       VARCHAR(150)    NOT NULL,
    email_cliente       VARCHAR(150)    UNIQUE NOT NULL,
    cpf_cliente         CHAR(11)        UNIQUE NOT NULL,
    data_cadastro       TIMESTAMP       DEFAULT NOW()
);

CREATE TABLE ingressos (
    id_ingresso         SERIAL          PRIMARY KEY,
    id_cliente          INT             NOT NULL,
    id_setor            INT             NOT NULL,
    data_compra         TIMESTAMP       DEFAULT NOW(),
    status_ingresso     VARCHAR(10)     DEFAULT 'ativo'
                        CHECK (status_ingresso IN ('ativo', 'cancelado', 'usado')),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
    FOREIGN KEY (id_setor)   REFERENCES setores(id_setor)
);
  
INSERT INTO shows (nome_show, cidade_show, data_show, local_show) VALUES
('BTS WORLD TOUR - BRASIL', 'São Paulo', '2026-09-15 20:00:00', 'Allianz Parque');
 
INSERT INTO setores (id_show, nome_setor, capacidade_setor, preco_setor) VALUES
(1, 'Pista Premium', 5000,  890.00),
(1, 'Pista',         8000,  590.00),
(1, 'Arquibancada',  20000, 290.00),
(1, 'Camarote',      500,   1500.00);
 
INSERT INTO clientes (nome_completo, email_cliente, cpf_cliente)
SELECT
    (ARRAY['Ana','Carlos','Mariana','Pedro','Julia','Lucas',
           'Beatriz','Felipe','Gabriela','Matheus'])[floor(random()*10+1)]
    || ' ' ||
    (ARRAY['Silva','Santos','Oliveira','Souza','Lima',
           'Pereira','Costa','Ferreira','Rocha','Alves'])[floor(random()*10+1)],
    'cliente' || numero_cliente || '@email.com',
    LPAD(numero_cliente::TEXT, 11, '0')
FROM generate_series(1, 10000) AS numero_cliente;

-- Geração de 5 milhões de registros para simular um ambiente de alta concorrência
-- Essa parte é essencial para validar o ganho de performance das Materialized Views.

INSERT INTO ingressos (id_cliente, id_setor, data_compra, status_ingresso)
SELECT
    (random() * 9999 + 1)::INT,
    (random() * 3   + 1)::INT,
    NOW() - (random() * 30)::INT * INTERVAL '1 day',
    CASE WHEN random() > 0.05 THEN 'ativo' ELSE 'cancelado' END
FROM generate_series(1, 5000000);


-- primeiro nível de lentidão: Disponibilidade de ingressos por setor 

CREATE OR REPLACE VIEW view_disponibilidade_por_setor AS
SELECT
    shows.nome_show                                                         AS nome_do_show,
    shows.local_show                                                        AS local_do_show,
    shows.data_show                                                         AS data_do_show,
    setores.nome_setor                                                      AS nome_do_setor,
    setores.capacidade_setor                                                AS total_de_lugares_no_setor,
    COUNT(ingressos.id_ingresso)                                            AS total_ingressos_vendidos,
    (setores.capacidade_setor - COUNT(ingressos.id_ingresso))               AS total_lugares_disponiveis,
    ROUND(COUNT(ingressos.id_ingresso)::NUMERIC
          / setores.capacidade_setor * 100, 1)                              AS percentual_de_ocupacao,
    setores.preco_setor                                                     AS preco_do_ingresso,
    SUM(setores.preco_setor)
        FILTER (WHERE ingressos.status_ingresso = 'ativo')                  AS receita_total_do_setor
FROM shows
JOIN setores        ON setores.id_show          = shows.id_show
LEFT JOIN ingressos ON ingressos.id_setor        = setores.id_setor
                   AND ingressos.status_ingresso = 'ativo'
GROUP BY
    shows.id_show,
    shows.nome_show,
    shows.local_show,
    shows.data_show,
    setores.id_setor,
    setores.nome_setor,
    setores.capacidade_setor,
    setores.preco_setor
ORDER BY setores.preco_setor DESC;


-- segundo nível de lentidão: Faturamento total por dia de vendas

CREATE OR REPLACE VIEW view_faturamento_por_dia AS
SELECT
    DATE(ingressos.data_compra)                                             AS data_da_venda,
    shows.nome_show                                                         AS nome_do_show,
    COUNT(ingressos.id_ingresso)                                            AS quantidade_ingressos_vendidos_no_dia,
    SUM(setores.preco_setor)                                                AS receita_total_do_dia,
    ROUND(AVG(setores.preco_setor), 2)                                      AS preco_medio_do_ingresso_no_dia,
    MAX(setores.preco_setor)                                                AS ingresso_mais_caro_do_dia,
    MIN(setores.preco_setor)                                                AS ingresso_mais_barato_do_dia
FROM ingressos
JOIN setores ON setores.id_setor  = ingressos.id_setor
JOIN shows   ON shows.id_show     = setores.id_show
WHERE ingressos.status_ingresso = 'ativo'
GROUP BY
    DATE(ingressos.data_compra),
    shows.id_show,
    shows.nome_show
ORDER BY data_da_venda DESC;

-- terceiro nível: Receita acumulada por setor dia a dia

CREATE OR REPLACE VIEW view_receita_acumulada_por_setor AS
SELECT
    nome_do_setor,
    data_da_venda,
    receita_do_dia,
    SUM(receita_do_dia) OVER (
        PARTITION BY nome_do_setor
        ORDER BY data_da_venda
    )                                                                       AS receita_acumulada_ate_este_dia
FROM (
    SELECT
        setores.nome_setor                                                  AS nome_do_setor,
        DATE(ingressos.data_compra)                                         AS data_da_venda,
        SUM(setores.preco_setor)                                            AS receita_do_dia
    FROM ingressos
    JOIN setores ON setores.id_setor = ingressos.id_setor
    WHERE ingressos.status_ingresso = 'ativo'
    GROUP BY
        setores.nome_setor,
        DATE(ingressos.data_compra)
) AS receita_diaria_por_setor
ORDER BY nome_do_setor, data_da_venda;

-- plano de execução:

-- primeiro nível:

EXPLAIN ANALYZE
SELECT * FROM view_disponibilidade_por_setor;

-- segundo nível:

EXPLAIN ANALYZE
SELECT * FROM view_faturamento_por_dia;

-- terceiro nível:

EXPLAIN ANALYZE
SELECT * FROM view_receita_acumulada_por_setor;

SELECT * FROM views_simples_lento.view_disponibilidade_por_setor;

--/////////////////////////////////////////////////////////////////////////

-- INÍCIO DA OTIMIZAÇÃO (MATERIALIZED VIEWS)

SET search_path TO views_otimizado_materializadas, public; --Se você rodou o primeiro SET para os arquivos ficarem organizados, é importante que quando roda esse SET, colocar o public, se não, vai ter erro


-- Uso de Materialized View para evitar o reprocessamento de 5M de linhas a cada consulta.
-- Os dados são persistidos em disco, reduzindo o custo de CPU e I/O.

CREATE MATERIALIZED VIEW view_materializada_disponibilidade_por_setor AS
SELECT
    shows.nome_show                                                         AS nome_do_show,
    shows.local_show                                                        AS local_do_show,
    shows.data_show                                                         AS data_do_show,
    setores.id_setor                                                        AS id_do_setor,
    setores.nome_setor                                                      AS nome_do_setor,
    setores.capacidade_setor                                                AS total_de_lugares_no_setor,
    COUNT(ingressos.id_ingresso)                                            AS total_ingressos_vendidos,
    (setores.capacidade_setor - COUNT(ingressos.id_ingresso))               AS total_lugares_disponiveis,
    ROUND(COUNT(ingressos.id_ingresso)::NUMERIC
          / setores.capacidade_setor * 100, 1)                              AS percentual_de_ocupacao,
    setores.preco_setor                                                     AS preco_do_ingresso,
    SUM(setores.preco_setor)
        FILTER (WHERE ingressos.status_ingresso = 'ativo')                  AS receita_total_do_setor
FROM shows
JOIN setores        ON setores.id_show          = shows.id_show
LEFT JOIN ingressos ON ingressos.id_setor        = setores.id_setor
                   AND ingressos.status_ingresso = 'ativo'
GROUP BY
    shows.id_show,
    shows.nome_show,
    shows.local_show,
    shows.data_show,
    setores.id_setor,
    setores.nome_setor,
    setores.capacidade_setor,
    setores.preco_setor
ORDER BY setores.preco_setor DESC
WITH DATA;
 
CREATE INDEX idx_disponibilidade_id_setor
    ON view_materializada_disponibilidade_por_setor (id_do_setor);
 
CREATE INDEX idx_disponibilidade_percentual_ocupacao
    ON view_materializada_disponibilidade_por_setor (percentual_de_ocupacao DESC);
 

CREATE MATERIALIZED VIEW view_materializada_faturamento_por_dia AS
SELECT
    DATE(ingressos.data_compra)                                             AS data_da_venda,
    shows.id_show                                                           AS id_do_show,
    shows.nome_show                                                         AS nome_do_show,
    COUNT(ingressos.id_ingresso)                                            AS quantidade_ingressos_vendidos_no_dia,
    SUM(setores.preco_setor)                                                AS receita_total_do_dia,
    ROUND(AVG(setores.preco_setor), 2)                                      AS preco_medio_do_ingresso_no_dia,
    MAX(setores.preco_setor)                                                AS ingresso_mais_caro_do_dia,
    MIN(setores.preco_setor)                                                AS ingresso_mais_barato_do_dia
FROM ingressos
JOIN setores ON setores.id_setor  = ingressos.id_setor
JOIN shows   ON shows.id_show     = setores.id_show
WHERE ingressos.status_ingresso = 'ativo'
GROUP BY
    DATE(ingressos.data_compra),
    shows.id_show,
    shows.nome_show
ORDER BY data_da_venda DESC
WITH DATA;

-- Índice B-Tree para otimizar filtros de data. 
-- Transforma uma busca sequencial em busca logarítmica.
 
CREATE INDEX idx_faturamento_data_da_venda
    ON view_materializada_faturamento_por_dia (data_da_venda DESC);
 
CREATE INDEX idx_faturamento_id_do_show
    ON view_materializada_faturamento_por_dia (id_do_show);


CREATE MATERIALIZED VIEW view_materializada_receita_acumulada_por_setor AS
SELECT
    nome_do_setor,
    data_da_venda,
    receita_do_dia,
    SUM(receita_do_dia) OVER (
        PARTITION BY nome_do_setor
        ORDER BY data_da_venda
    )                                                                       AS receita_acumulada_ate_este_dia
FROM (
    SELECT
        setores.nome_setor                                                  AS nome_do_setor,
        DATE(ingressos.data_compra)                                         AS data_da_venda,
        SUM(setores.preco_setor)                                            AS receita_do_dia
    FROM ingressos
    JOIN setores ON setores.id_setor = ingressos.id_setor
    WHERE ingressos.status_ingresso = 'ativo'
    GROUP BY
        setores.nome_setor,
        DATE(ingressos.data_compra)
) AS receita_diaria_por_setor
ORDER BY nome_do_setor, data_da_venda
WITH DATA;
 
CREATE INDEX idx_receita_acumulada_nome_do_setor
    ON view_materializada_receita_acumulada_por_setor (nome_do_setor, data_da_venda);

SELECT * FROM view_materializada_disponibilidade_por_setor;
 
SELECT * FROM view_materializada_disponibilidade_por_setor
WHERE percentual_de_ocupacao > 80;
 
SELECT * FROM view_materializada_faturamento_por_dia
WHERE data_da_venda >= CURRENT_DATE - INTERVAL '7 days';
 
SELECT * FROM view_materializada_receita_acumulada_por_setor
WHERE nome_do_setor = 'Pista Premium';

EXPLAIN ANALYZE
SELECT * FROM view_materializada_disponibilidade_por_setor;
 
EXPLAIN ANALYZE
SELECT * FROM view_materializada_faturamento_por_dia;
 
EXPLAIN ANALYZE
SELECT * FROM view_materializada_receita_acumulada_por_setor

REFRESH MATERIALIZED VIEW view_materializada_disponibilidade_por_setor;
REFRESH MATERIALIZED VIEW view_materializada_faturamento_por_dia;
REFRESH MATERIALIZED VIEW view_materializada_receita_acumulada_por_setor;
 

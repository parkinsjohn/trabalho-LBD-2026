-- ============================================================
-- 04-CONSULTAS.SQL - LIGA FACOM FANTASY
-- Esquema: fantasy_game (PostgreSQL 16+)
-- ============================================================


-- ------------------------------------------------------------
-- (a) Visao do mercado:
-- Para cada atleta disponivel para escalacao na rodada aberta,
-- exibe apelido, clube, posicao, situacao, preco atual, media
-- e pontuacao na ultima rodada consolidada em que entrou em campo.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW fantasy_game.vw_mercado AS
WITH rodada_aberta AS (
    SELECT e.numero_rodada
      FROM fantasy_game.estado e
     WHERE e.estado = 'aberta'
     ORDER BY e.numero_rodada ASC
     LIMIT 1
),
rodadas_consolidadas AS (
    SELECT e.numero_rodada
      FROM fantasy_game.estado e
     WHERE e.estado = 'consolidada'
),
participacoes_consolidadas AS (
    SELECT
        atl.id_atleta,
        rc.numero_rodada,
        COALESCE(bool_or(at.entrou_em_campo), false) AS entrou_em_campo,
        fantasy_game.fn_pontuacao_atleta_rodada(atl.id_atleta, rc.numero_rodada) AS pontos_rodada
    FROM fantasy_game.atletas atl
    CROSS JOIN rodadas_consolidadas rc
    LEFT JOIN fantasy_game.partida p
      ON p.numero_rodada = rc.numero_rodada
    LEFT JOIN fantasy_game.atua at
      ON at.id_atleta = atl.id_atleta
     AND at.indicacao_partida = p.indicacao_partida
    GROUP BY atl.id_atleta, rc.numero_rodada
),
resumo_historico AS (
    SELECT
        pc.id_atleta,
        COALESCE(AVG(pc.pontos_rodada) FILTER (WHERE pc.entrou_em_campo), 0.00)::numeric(8, 2) AS media_pontos,
        (
            SELECT pc2.pontos_rodada
              FROM participacoes_consolidadas pc2
             WHERE pc2.id_atleta = pc.id_atleta
               AND pc2.entrou_em_campo IS TRUE
             ORDER BY pc2.numero_rodada DESC
             LIMIT 1
        )::numeric(8, 2) AS pontuacao_ultima_rodada_jogada
    FROM participacoes_consolidadas pc
    GROUP BY pc.id_atleta
)
SELECT
    atl.id_atleta,
    atl.apelido,
    cl.nome AS clube,
    pos.nome AS posicao,
    sit.nome AS situacao,
    atl.preco_atual,
    COALESCE(rh.media_pontos, 0.00)::numeric(8, 2) AS media,
    rh.pontuacao_ultima_rodada_jogada
FROM rodada_aberta ra
CROSS JOIN fantasy_game.atletas atl
LEFT JOIN fantasy_game.situacao sit
  ON sit.id_situacao = atl.id_situacao
LEFT JOIN fantasy_game.posicao pos
  ON pos.id_posicao = atl.id_posicao
LEFT JOIN fantasy_game.pertence pert
  ON pert.id_atleta = atl.id_atleta
 AND pert.numero_rodada = ra.numero_rodada
LEFT JOIN fantasy_game.clube cl
  ON cl.id_clube = pert.id_clube
LEFT JOIN resumo_historico rh
  ON rh.id_atleta = atl.id_atleta
WHERE lower(trim(sit.nome)) IN ('provavel', 'dúvida', 'duvida');


-- ------------------------------------------------------------
-- (b) Visao do ranking:
-- Para cada liga e cada tecnico participante, exibe a pontuacao
-- acumulada e a posicao do tecnico na liga. Empates ocupam a
-- mesma posicao.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW fantasy_game.vw_ranking AS
WITH pontos_consolidados_tecnico AS (
    SELECT
        esc.id_tecnico,
        COALESCE(
            SUM(
                COALESCE(
                    esc.pontuacao_total,
                    fantasy_game.fn_pontuacao_escalacao(esc.id_escalacao)
                )
            ),
            0.00
        )::numeric(10, 2) AS pontuacao_acumulada
    FROM fantasy_game.escalacao esc
    JOIN fantasy_game.estado est
      ON est.numero_rodada = esc.numero_rodada
    WHERE est.estado = 'consolidada'
      AND esc.confirmada IS TRUE
    GROUP BY esc.id_tecnico
)
SELECT
    l.id_liga,
    l.nome AS nome_liga,
    tec.id_tecnico,
    tec.nome AS nome_tecnico,
    tec."time" AS nome_time,
    COALESCE(pct.pontuacao_acumulada, 0.00)::numeric(10, 2) AS pontuacao_acumulada,
    RANK() OVER (
        PARTITION BY l.id_liga
        ORDER BY COALESCE(pct.pontuacao_acumulada, 0.00) DESC
    ) AS posicao_na_liga
FROM fantasy_game.liga l
JOIN fantasy_game.participa p
  ON p.id_liga = l.id_liga
JOIN fantasy_game.tecnico tec
  ON tec.id_tecnico = p.id_tecnico
LEFT JOIN pontos_consolidados_tecnico pct
  ON pct.id_tecnico = tec.id_tecnico;


-- ------------------------------------------------------------
-- (c) Os 5 atletas de cada posicao com melhor custo-beneficio
-- (media de pontos dividida pelo preco atual), considerando
-- apenas atletas que entraram em campo em pelo menos 3 rodadas.
-- ------------------------------------------------------------
WITH rodadas_consolidadas AS (
    SELECT e.numero_rodada
      FROM fantasy_game.estado e
     WHERE e.estado = 'consolidada'
),
jogos_atleta AS (
    SELECT
        atl.id_atleta,
        atl.apelido,
        atl.id_posicao,
        atl.preco_atual,
        rc.numero_rodada,
        COALESCE(bool_or(at.entrou_em_campo), false) AS entrou_em_campo,
        fantasy_game.fn_pontuacao_atleta_rodada(atl.id_atleta, rc.numero_rodada) AS pontos
    FROM fantasy_game.atletas atl
    CROSS JOIN rodadas_consolidadas rc
    LEFT JOIN fantasy_game.partida p
      ON p.numero_rodada = rc.numero_rodada
    LEFT JOIN fantasy_game.atua at
      ON at.id_atleta = atl.id_atleta
     AND at.indicacao_partida = p.indicacao_partida
    GROUP BY atl.id_atleta, atl.apelido, atl.id_posicao, atl.preco_atual, rc.numero_rodada
),
metricas_cb AS (
    SELECT
        ja.id_atleta,
        ja.apelido,
        pos.nome AS posicao,
        ja.preco_atual,
        COUNT(*) FILTER (WHERE ja.entrou_em_campo) AS rodadas_jogadas,
        AVG(ja.pontos) FILTER (WHERE ja.entrou_em_campo)::numeric(8, 2) AS media_pontos,
        (
            (AVG(ja.pontos) FILTER (WHERE ja.entrou_em_campo))
            / NULLIF(ja.preco_atual, 0)
        )::numeric(10, 4) AS custo_beneficio
    FROM jogos_atleta ja
    JOIN fantasy_game.posicao pos
      ON pos.id_posicao = ja.id_posicao
    GROUP BY ja.id_atleta, ja.apelido, pos.nome, ja.preco_atual
    HAVING COUNT(*) FILTER (WHERE ja.entrou_em_campo) >= 3
       AND COALESCE(ja.preco_atual, 0) > 0
),
ranqueado_posicao AS (
    SELECT
        mc.*,
        ROW_NUMBER() OVER (
            PARTITION BY mc.posicao
            ORDER BY mc.custo_beneficio DESC, mc.media_pontos DESC, mc.apelido ASC
        ) AS colocacao_posicao
    FROM metricas_cb mc
)
SELECT
    posicao,
    colocacao_posicao,
    id_atleta,
    apelido,
    preco_atual,
    rodadas_jogadas,
    media_pontos,
    custo_beneficio
FROM ranqueado_posicao
WHERE colocacao_posicao <= 5
ORDER BY posicao, colocacao_posicao;


-- ------------------------------------------------------------
-- (d) O "top da rodada": para uma rodada consolidada, o tecnico
-- de maior pontuacao, o nome do seu time, a pontuacao e o
-- capitao escolhido. Em caso de empate, vence quem confirmou
-- a escalacao primeiro.
-- Parametro de exemplo: p_numero_rodada = 31
-- ------------------------------------------------------------
WITH escalacoes_rodada AS (
    SELECT
        esc.id_escalacao,
        esc.numero_rodada,
        esc.id_tecnico,
        esc.data_confirmacao,
        COALESCE(
            esc.pontuacao_total,
            fantasy_game.fn_pontuacao_escalacao(esc.id_escalacao)
        )::numeric(8, 2) AS pontuacao
    FROM fantasy_game.escalacao esc
    JOIN fantasy_game.estado est
      ON est.numero_rodada = esc.numero_rodada
    WHERE esc.numero_rodada = 31 -- parametro: p_numero_rodada
      AND est.estado = 'consolidada'
      AND esc.confirmada IS TRUE
)
SELECT
    er.numero_rodada,
    tec.nome AS nome_tecnico,
    tec."time" AS nome_time,
    er.pontuacao,
    atl_cap.apelido AS capitao_escolhido,
    er.data_confirmacao
FROM escalacoes_rodada er
JOIN fantasy_game.tecnico tec
  ON tec.id_tecnico = er.id_tecnico
LEFT JOIN fantasy_game.escala_atleta ea_cap
  ON ea_cap.id_escalacao = er.id_escalacao
 AND ea_cap.eh_capitao IS TRUE
LEFT JOIN fantasy_game.atletas atl_cap
  ON atl_cap.id_atleta = ea_cap.id_atleta
ORDER BY er.pontuacao DESC, er.data_confirmacao ASC NULLS LAST, tec.id_tecnico ASC
LIMIT 1;


-- ------------------------------------------------------------
-- (e) O clube com mais jogos sem sofrer gol nas ultimas 5
-- rodadas consolidadas, calculado a partir dos placares das
-- partidas.
-- ------------------------------------------------------------
WITH ultimas_5_consolidadas AS (
    SELECT e.numero_rodada
      FROM fantasy_game.estado e
     WHERE e.estado = 'consolidada'
     ORDER BY e.numero_rodada DESC
     LIMIT 5
),
participacoes_jogo AS (
    -- Como mandante: sofreu gols equivalentes a placar_visitante
    SELECT
        p.id_clube_mandante AS id_clube,
        CASE WHEN p.placar_visitante = 0 THEN 1 ELSE 0 END AS sem_sofrer_gol
    FROM fantasy_game.partida p
    JOIN ultimas_5_consolidadas u
      ON u.numero_rodada = p.numero_rodada
    WHERE COALESCE(p.valida, true) IS TRUE
      AND p.placar_visitante IS NOT NULL
      AND p.id_clube_mandante IS NOT NULL

    UNION ALL

    -- Como visitante: sofreu gols equivalentes a placar_mandante
    SELECT
        p.id_clube_visitante AS id_clube,
        CASE WHEN p.placar_mandante = 0 THEN 1 ELSE 0 END AS sem_sofrer_gol
    FROM fantasy_game.partida p
    JOIN ultimas_5_consolidadas u
      ON u.numero_rodada = p.numero_rodada
    WHERE COALESCE(p.valida, true) IS TRUE
      AND p.placar_mandante IS NOT NULL
      AND p.id_clube_visitante IS NOT NULL
),
contagem_sg AS (
    SELECT
        cl.id_clube,
        cl.nome AS clube,
        cl.abreviacao,
        COALESCE(SUM(pj.sem_sofrer_gol), 0) AS jogos_sem_sofrer_gol
    FROM fantasy_game.clube cl
    LEFT JOIN participacoes_jogo pj
      ON pj.id_clube = cl.id_clube
    GROUP BY cl.id_clube, cl.nome, cl.abreviacao
)
SELECT
    id_clube,
    clube,
    abreviacao,
    jogos_sem_sofrer_gol
FROM contagem_sg
ORDER BY jogos_sem_sofrer_gol DESC, clube ASC
LIMIT 1;


-- ------------------------------------------------------------
-- (f) O atleta mais escolhido como capitao dentro de uma liga,
-- com a quantidade de vezes.
-- Parametro de exemplo: p_id_liga = 1
-- ------------------------------------------------------------
SELECT
    p.id_liga,
    l.nome AS nome_liga,
    atl.id_atleta,
    atl.apelido,
    COUNT(*) AS vezes_capitao
FROM fantasy_game.participa p
JOIN fantasy_game.liga l
  ON l.id_liga = p.id_liga
JOIN fantasy_game.escalacao esc
  ON esc.id_tecnico = p.id_tecnico
JOIN fantasy_game.escala_atleta ea
  ON ea.id_escalacao = esc.id_escalacao
 AND ea.eh_capitao IS TRUE
JOIN fantasy_game.atletas atl
  ON atl.id_atleta = ea.id_atleta
WHERE p.id_liga = 1 -- parametro: p_id_liga
GROUP BY p.id_liga, l.nome, atl.id_atleta, atl.apelido
ORDER BY vezes_capitao DESC, atl.apelido ASC
LIMIT 1;


-- ------------------------------------------------------------
-- (g) Os tecnicos que nunca escalaram nenhum atleta de um
-- clube informado.
-- Parametro de exemplo: p_id_clube = 262
-- ------------------------------------------------------------
SELECT
    tec.id_tecnico,
    tec.nome AS nome_tecnico,
    tec."time" AS nome_time
FROM fantasy_game.tecnico tec
WHERE NOT EXISTS (
    SELECT 1
      FROM fantasy_game.escalacao esc
      JOIN fantasy_game.escala_atleta ea
        ON ea.id_escalacao = esc.id_escalacao
      JOIN fantasy_game.pertence pert
        ON pert.id_atleta = ea.id_atleta
       AND pert.numero_rodada = esc.numero_rodada
     WHERE esc.id_tecnico = tec.id_tecnico
       AND pert.id_clube = 262 -- parametro: p_id_clube
);


-- ------------------------------------------------------------
-- (h) Os atletas que, em todas as rodadas consolidadas em que
-- entraram em campo, pontuaram acima da media da sua posicao
-- naquela rodada.
-- ------------------------------------------------------------
WITH rodadas_consolidadas AS (
    SELECT e.numero_rodada
      FROM fantasy_game.estado e
     WHERE e.estado = 'consolidada'
),
atuacoes_rodada AS (
    SELECT
        atl.id_atleta,
        atl.apelido,
        atl.id_posicao,
        rc.numero_rodada,
        COALESCE(bool_or(at.entrou_em_campo), false) AS entrou_em_campo,
        fantasy_game.fn_pontuacao_atleta_rodada(atl.id_atleta, rc.numero_rodada) AS pontos
    FROM fantasy_game.atletas atl
    CROSS JOIN rodadas_consolidadas rc
    LEFT JOIN fantasy_game.partida p
      ON p.numero_rodada = rc.numero_rodada
    LEFT JOIN fantasy_game.atua at
      ON at.id_atleta = atl.id_atleta
     AND at.indicacao_partida = p.indicacao_partida
    GROUP BY atl.id_atleta, atl.apelido, atl.id_posicao, rc.numero_rodada
),
media_posicao_rodada AS (
    SELECT
        ar.id_posicao,
        ar.numero_rodada,
        AVG(ar.pontos) AS media_pos
    FROM atuacoes_rodada ar
    WHERE ar.entrou_em_campo IS TRUE
    GROUP BY ar.id_posicao, ar.numero_rodada
),
jogos_validos_atleta AS (
    SELECT
        ar.id_atleta,
        ar.apelido,
        pos.nome AS posicao,
        ar.numero_rodada,
        ar.pontos,
        mpr.media_pos
    FROM atuacoes_rodada ar
    JOIN media_posicao_rodada mpr
      ON mpr.id_posicao = ar.id_posicao
     AND mpr.numero_rodada = ar.numero_rodada
    JOIN fantasy_game.posicao pos
      ON pos.id_posicao = ar.id_posicao
    WHERE ar.entrou_em_campo IS TRUE
)
SELECT
    jva.id_atleta,
    jva.apelido,
    jva.posicao,
    COUNT(*) AS rodadas_avaliadas
FROM jogos_validos_atleta jva
GROUP BY jva.id_atleta, jva.apelido, jva.posicao
HAVING COUNT(*) > 0
   AND BOOL_AND(jva.pontos > jva.media_pos)
ORDER BY rodadas_avaliadas DESC, jva.apelido ASC;


-- ------------------------------------------------------------
-- (i) A evolucao do patrimonio de um tecnico rodada a rodada,
-- com a variacao em relacao a rodada anterior.
-- Parametro de exemplo: p_id_tecnico = 1
-- ------------------------------------------------------------
WITH variacao_escalacao AS (
    SELECT
        esc.id_tecnico,
        esc.numero_rodada,
        COALESCE(
            SUM(COALESCE(ve.preco::numeric(12, 2), atl.preco_atual) - COALESCE(ea.preco_pago, 0.00)),
            0.00
        )::numeric(10, 2) AS variacao_rodada
    FROM fantasy_game.escalacao esc
    JOIN fantasy_game.estado est
      ON est.numero_rodada = esc.numero_rodada
    LEFT JOIN fantasy_game.escala_atleta ea
      ON ea.id_escalacao = esc.id_escalacao
    LEFT JOIN fantasy_game.atletas atl
      ON atl.id_atleta = ea.id_atleta
    LEFT JOIN fantasy_game.vale_em ve
      ON ve.id_atleta = ea.id_atleta
     AND ve.numero_rodada = esc.numero_rodada
    WHERE esc.id_tecnico = 1 -- parametro: p_id_tecnico
      AND est.estado = 'consolidada'
      AND esc.confirmada IS TRUE
    GROUP BY esc.id_tecnico, esc.numero_rodada
),
serie_patrimonio AS (
    SELECT
        tec.id_tecnico,
        tec.nome AS nome_tecnico,
        ve.numero_rodada,
        ve.variacao_rodada,
        (
            100.00 + SUM(ve.variacao_rodada) OVER (
                PARTITION BY ve.id_tecnico
                ORDER BY ve.numero_rodada ASC
            )
        )::numeric(10, 2) AS patrimonio_na_rodada
    FROM variacao_escalacao ve
    JOIN fantasy_game.tecnico tec
      ON tec.id_tecnico = ve.id_tecnico
)
SELECT
    id_tecnico,
    nome_tecnico,
    numero_rodada,
    patrimonio_na_rodada,
    (
        patrimonio_na_rodada
        - LAG(patrimonio_na_rodada, 1, 100.00) OVER (
            PARTITION BY id_tecnico
            ORDER BY numero_rodada ASC
        )
    )::numeric(10, 2) AS variacao_vs_rodada_anterior
FROM serie_patrimonio
ORDER BY numero_rodada ASC;


-- ------------------------------------------------------------
-- (j) As ligas com pelo menos 3 participantes cuja pontuacao
-- media por tecnico, no acumulado, seja maior que a media
-- geral de todos os tecnicos do sistema.
-- ------------------------------------------------------------
WITH pontos_tecnico_acumulado AS (
    SELECT
        tec.id_tecnico,
        COALESCE(
            SUM(
                COALESCE(
                    esc.pontuacao_total,
                    fantasy_game.fn_pontuacao_escalacao(esc.id_escalacao)
                )
            ) FILTER (WHERE est.estado = 'consolidada' AND esc.confirmada IS TRUE),
            0.00
        )::numeric(10, 2) AS pontuacao_acumulada
    FROM fantasy_game.tecnico tec
    LEFT JOIN fantasy_game.escalacao esc
      ON esc.id_tecnico = tec.id_tecnico
    LEFT JOIN fantasy_game.estado est
      ON est.numero_rodada = esc.numero_rodada
    GROUP BY tec.id_tecnico
),
media_geral_sistema AS (
    SELECT AVG(pontuacao_acumulada)::numeric(10, 2) AS media_geral
      FROM pontos_tecnico_acumulado
),
medias_por_liga AS (
    SELECT
        l.id_liga,
        l.nome AS nome_liga,
        COUNT(p.id_tecnico) AS qtd_participantes,
        AVG(pta.pontuacao_acumulada)::numeric(10, 2) AS media_por_tecnico_liga
    FROM fantasy_game.liga l
    JOIN fantasy_game.participa p
      ON p.id_liga = l.id_liga
    JOIN pontos_tecnico_acumulado pta
      ON pta.id_tecnico = p.id_tecnico
    GROUP BY l.id_liga, l.nome
    HAVING COUNT(p.id_tecnico) >= 3
)
SELECT
    mpl.id_liga,
    mpl.nome_liga,
    mpl.qtd_participantes,
    mpl.media_por_tecnico_liga,
    mgs.media_geral AS media_geral_sistema
FROM medias_por_liga mpl
CROSS JOIN media_geral_sistema mgs
WHERE mpl.media_por_tecnico_liga > mgs.media_geral
ORDER BY mpl.media_por_tecnico_liga DESC, mpl.nome_liga ASC;


-- ------------------------------------------------------------
-- (k) A "selecao da rodada" simplificada: para uma rodada
-- consolidada, o atleta de maior pontuacao de cada posicao,
-- considerando apenas atletas cujo preco naquela rodada era
-- de no maximo C$ 12,00, e o custo total desse time.
-- Parametro de exemplo: p_numero_rodada = 31
-- ------------------------------------------------------------
WITH candidatos_rodada AS (
    SELECT
        atl.id_atleta,
        atl.apelido,
        pos.id_posicao,
        pos.nome AS posicao,
        COALESCE(ve.preco::numeric(12, 2), atl.preco_atual) AS preco_na_rodada,
        fantasy_game.fn_pontuacao_atleta_rodada(atl.id_atleta, 31) AS pontuacao_rodada -- parametro: p_numero_rodada
    FROM fantasy_game.atletas atl
    JOIN fantasy_game.posicao pos
      ON pos.id_posicao = atl.id_posicao
    JOIN fantasy_game.estado est
      ON est.numero_rodada = 31 -- parametro: p_numero_rodada
     AND est.estado = 'consolidada'
    LEFT JOIN fantasy_game.vale_em ve
      ON ve.id_atleta = atl.id_atleta
     AND ve.numero_rodada = 31 -- parametro: p_numero_rodada
    WHERE COALESCE(ve.preco::numeric(12, 2), atl.preco_atual) <= 12.00
),
melhor_por_posicao AS (
    SELECT DISTINCT ON (cr.id_posicao)
        cr.id_posicao,
        cr.posicao,
        cr.id_atleta,
        cr.apelido,
        cr.preco_na_rodada,
        cr.pontuacao_rodada
    FROM candidatos_rodada cr
    ORDER BY cr.id_posicao ASC, cr.pontuacao_rodada DESC, cr.preco_na_rodada ASC, cr.id_atleta ASC
)
SELECT
    mpp.posicao,
    mpp.id_atleta,
    mpp.apelido,
    mpp.preco_na_rodada,
    mpp.pontuacao_rodada,
    SUM(mpp.preco_na_rodada) OVER ()::numeric(12, 2) AS custo_total_selecao
FROM melhor_por_posicao mpp
ORDER BY mpp.id_posicao ASC;
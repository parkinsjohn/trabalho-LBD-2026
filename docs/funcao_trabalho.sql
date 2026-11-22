--===============================================================
-- FUNÇÕES PL/pgSQL para DDL (trabalho_ddl.sql)
--Esquema: fatasy_game
--===============================================================

--1. CALCULAR PONTUAÇÃO DE UM ATLETA EM UMA PARTIDA
-- usa gs.indicao_partida
-- e faz trim em sigla porque sigla é character(10)
CREATE OR REPLACE FUNCTION fantasy_game.fn_calcular_pontuacao_atleta(
	p_id_atleta integer,
	p_indicacao_partida integer
)
RETURNS numeric(8, 2)
LANGUAGE plpgsql
AS $$
DECLARE
	v_pontuacao numeric(8, 2);
BEGIN
	SELECT COALESCE(SUM(gs.quantidade * ts.valor_pontos), 0.00)::numeric(8, 2)
	  INTO v_pontuacao
	  FROM fantasy_game.gera_scout gs
	  JOIN fantasy_game.tipo_scout ts
	  	ON trim(ts.sigla) = trim(gs.sigla)
	  JOIN fantasy_game.atletas a
	  	ON a.id_atleta = gs.id_atleta
      JOIN fantasy_game.pontua_para pp
		ON trim(pp.sigla) = trim(gs.sigla)
	   AND pp.id_posicao = a.id_posicao
	 WHERE gs.id_atleta = p_id_atleta
	   AND gs.indicao_partida = p_indicacao_partida;
     
	 RETURN COALESCE(v_pontuacao, 0.00);
END;
$$;

-- 2. CONSULTA ESTADO DA RODADA
-- Usa trim(e.estado) porque estado é character(25) no ddl
CREATE OR REPLACE FUNCTION fantasy_game.fn_estado_rodada(
	p_numero_rodada integer
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado text;
BEGIN
	SELECT trim(e.estado)
	  INTO v_estado
	  FROM fantasy_game.estado e
	 WHERE e.numero_rodada = p_numero_rodada
	 LIMIT 1;

	RETURN v_estado;
END;
$$;

-- 3. CALCULAR CUSTO TOTAL DE UMA ESCALA
--soma preco_pago (mumeric(12, 0) no ddl) e converte p/ numeric(10,2)
CREATE OR REPLACE FUNCTION fantasy_game.fn_custo_escalacao(
    p_id_escalacao integer
)
RETURNS numeric(10, 2)
LANGUAGE plpgsql
AS $$
DECLARE 
	v_custo numeric(10, 2);
BEGIN
	SELECT COALESCE(SUM(ea.preco_pago), 0)::numeric(10, 2)
	  INTO v_custo
	  FROM fantasy_game.escala_atleta ea
	 WHERE ea.id_escalacao = p_id_escalacao;

	RETURN COALESCE(v_custo, 0.00);
END;
$$;

-- 4. CALCULAR PONTUAÇÃO TOTAL DE UMA ESCALAÇÃO
-- soma pontuacao_roda dos atlteas escalados
-- rodada da escalção, aplicando 2x quando eh_capitao for true
CREATE OR REPLACE FUNCTION fantasy_game.fn_calcular_pontuacao_escalacao(
	p_id_escalacao integer
)
RETURNS numeric(8, 2)
LANGUAGE plpgsql
AS $$
DECLARE
	v_rodada integer;
	v_total numeric(8, 2);
BEGIN
	SELECT esc.numero_rodada
	  INTO v_rodada
	  FROM fantasy_game.escalacao esc
	WHERE esc.id_escalacao = p_id_escalacao;

   IF v_rodada IS NULL THEN
	   RETURN 0.00;
   END IF;

   SELECT COALESCE(
   			  SUM(COALESCE(at.potuacao_rodada, 0)::numeric(8, 2) *
				  CASE WHEN COALESCE(ea.eh_capitao, false) THEN 2.00 ELSE 1.00 END
			  ),
			  0.00
		  )::numeric(8, 2)
	 INTO v_total
	 FROM fantasy_game.escala_atleta ea
	 JOIN fantasy_game.partida p
	   ON p.numero_rodada = v_rodada
	 LEFT JOIN fantasy_game.atua at
	   ON at.id_atleta = ea.id_atleta
	  AND at.indicacao_partida = p.indicacao_partida
	WHERE ea.id_escalacao = p_id_escalacao;

   RETURN COALESCE(v_total, 0.00);
END;
$$;

-- 5. VERIFICAR SE A ESCALAÇÃO RESPEITA O ESQUEMA TÁTICO
-- usa UPPER(trim(pos.abreviacao)) porque abreviacao é charactr(15) no ddl
CREATE OR REPLACE FUNCTION fantasy_game.fn_validar_esquema_escalacao(
	p_id_escalacao integer
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
	v_qtd_gol smallint;
	v_qtd_lat smallint;
	v_qtd_zag smallint;
	v_qtd_mei smallint;
	v_qtd_ata smallint;
	v_qtd_tec smallint;
	
	v_real_gol smallint;
	v_real_lat smallint;
	v_real_zag smallint;
	v_real_mei smallint;
	v_real_ata smallint;
	v_real_tec smallint;
BEGIN
	SELECT et.qtd_gol, et.qtd_lat,  et.qtd_zag,  et.qtd_mei,  et.qtd_ata,  et.qtd_tec
	  INTO v_qtd_gol, v_qtd_lat, v_qtd_zag, v_qtd_mei, v_qtd_ata, v_qtd_tec
	  FROM fantasy_game.escalacao esc
	  JOIN fantasy_game.esquema_tatico et
	  	ON et.id_esquema = esc.id_esquema
	 WHERE esc.id_escalacao = p_id_escalacao;

	IF NOT FOUND THEN
		RETURN false;
	END IF;

	SELECT
		(COUNT(*) FILTER (WHERE upper(trim(pos.abreviacao)) IN ('GOL', 'G')))::smallint,
		(COUNT(*) FILTER (WHERE upper(trim(pos.abreviacao)) IN ('LAT', 'L')))::smallint,
		(COUNT(*) FILTER (WHERE upper(trim(pos.abreviacao)) IN ('ZAG', 'Z')))::smallint,
		(COUNT(*) FILTER (WHERE upper(trim(pos.abreviacao)) IN ('MEI', 'M')))::smallint,
		(COUNT(*) FILTER (WHERE upper(trim(pos.abreviacao)) IN ('ATA', 'A')))::smallint,
		(COUNT(*) FILTER (WHERE upper(trim(pos.abreviacao)) IN ('TEC', 'T')))::smallint
	  INTO v_real_gol, v_real_lat, v_real_zag, v_real_mei, v_real_ata, v_real_tec
	  FROM fantasy_game.escala_atleta ea
	  JOIN fantasy_game.atletas atl
	  	ON atl.id_atleta = ea.id_atleta
	  JOIN fantasy_game.posicao pos
	  	ON pos.id_posicao = atl.id_posicao
	 WHERE ea.id_escalacao = p_id_escalacao;

	RETURN (
		v_real_gol = v_qtd_gol AND
		v_real_lat = v_qtd_lat AND
		v_real_zag = v_qtd_zag AND
		v_real_mei = v_qtd_mei AND
		v_real_ata = v_qtd_ata AND
		v_real_tec = v_qtd_tec
	);
END;
$$;
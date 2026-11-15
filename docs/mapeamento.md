# Mapeamento Relacional - Liga FACOM Fantasy

## 1. Esquema Relacional e Regras de Mapeamento

### Entidades Fortes e Relacionamentos 1:N (Regras R1 e R4)

* **TECNICO** (``id_clube``, ``nome``, ``email``, ``apelido``, ``data_cadastro``, ``time``, ``patrimonio``)
    * Origem: **R1** (Entidade forte). email é chave candidata (UNIQUE).

* **CLUBE** (``id_clube``, ``nome``, ``abreviacao``, ``endereco_escudo``)
    * Origem: **R1** (Entidade forte).

* **POSICAO** (``id_posicao``, ``nome``, ``abrevicao``)
    * Origem: **R1** (Entidade forte).

* **SITUACAO** (id_situcao, nome``)
    * Origem: **R1** (Entidade forte).

* **ESQUEMA_TATICO** (``id_esquema``, ``nome``, ``qtd_gol``, ``qtd_lat``, ``qtd_zag``, ``qtd_mei``, ``qtd_ata``, ``qtd_tec``)
    * Origem: **R1** (Entidade forte; os atributos de quantidade por posição foram achatados em colunas).

* **RODADE** (``numero_rodada``, ``estado``)
    * Origem: **R1** (Entidade forte).

* **TIPO_SCOUT** (``sigla``, ``descricao``, ``valor_pontos``)
    * Origem: **R1** (Entidade forte).

* **LIGA** (``id_liga``, ``nome``, ``descricao``, ``codigo_convite``, ``limite_participantes``, ``publica``, ``id_tecnico_dono`` → **TECNICO**)
    * Origem: **R1** (Entidade forte) + **R4** (Relacionamentos 1:N possui e ``esta_em`` trazem as FKs de **POSICAO** e **SITUACAO**).

* **ATLETAS** (``id_atleta``, ``nome_completo``, ``apelido``, ``preco_atual``, ``id_posicao`` → **POSICAO**, ``id_situacao`` → **SITUACAO**)
    * Origem: **R1** (Entidade forte) + **R4** (Relacionamentos 1:N possui e esta_em trazem as FKs de **POSICAO** e **SITUACAO**).

* **PARTIDA** (``id_partida``, ``numero_rodada`` → **RODADA**, ``id_clube_mandante`` → **CLUBE**, ``id_clube_visitante`` → **CLUBE**, ``local``, ``data_hora``, ``placar_mandante``, ``placar_visitante``, ``valida``)
    * Origem: **R1** (Entidade forte) + **R4** (Relacionamentos 1:N contem, ``manda`` e ``visita`` trazem as FKS para o lado N).

* **ESCALACAO** (``id_escalacao``, ``id_tecnico`` → **TECNICO**, ``numero_rodada`` → **RODADA**, ``id_esquema`` → **ESQUEMA_TATICO**, ``confirmada``, ``data_confirmacao``, ``pontuacao_atual``)
    * Origem: **R1** (Entidade forte com chave substituta) + **R4** (Relacionamento 1:N ``monta``, ``referente_a`` e ``utiliza``). A combinação (``id_tecnico`, numero_rodada``) é chave candidata (UNIQUE).


---

### Relacionamento N:M e Ternários (Regras R5)

* **PARTICIPACAO_LIGA** (``id_tecnico`` → **TECNICO**, ``id_liga`` → **LIGA**, ``data_entrada``)
    * Origem: **R5** (Relacionamento N:M ``participa`` entre **TECNICO** e **LIGA**, trazendo o atributo ``data_entrada``).

* **ITEM_ESCALACAO** (``id_escalacao`` → **ESCALACAO**, ``id_atleta`` → **ATLETAS**, ``preco_pago``, ``eh_capitao``) 
    * Origem: **R5** (Relacionamento N:M ``escala_atleta`` entre **ESCALACAO** e **ATLETAS**, trazendo os atributos ``preco_pago`` e ``eh_capitao``).

* **HISTORICO_PRECO** (``id_atleta`` → **ATLETAS**, ``numero_rodada`` → **RODADA**, ``preco``)
    * Origem: **R5** (Relacionamento N:M ``vale_em`` entre **ATLETAS** e **RODADA** trazendo o atributo ``preco``).

* **ATLETAS_CLUBE_RODADA** (``id_atleta`` → **ATLETAS**, ``numero_rodada`` → **RODADA**, ``id_clube`` → **CLUBE** )
    * Origem: **R5** (Relacionamento ternário ``pertence_a``). Como a regra de negócio limita o atleta a no máximo um clube por rodada, a PK é composta apenas por (``id_atleta``, ``numero_rodada``), tendo ``id_clube`` como atributo/FK.

* **ATUA_PARTIDA** (``id_atleta`` → **ATLETAS**, ``id_partida`` → **PARTIDA**, ``entrou_em_campo``, ``pontucao_rodada``)
    * Origem: **R5** (Realacionamento N:M ``atua`` entre **ATLETAS** e **PARTIDA**, registrando se entrou em campo e a pontuação materializada).

* **ESTATISTICA_SCOUT** (``id_atleta`` → **ATLETAS** → ``id_partida`` → **PARTIDA**, ``sigla`` → **TIPO_SCOUT**, ``quantidade``)
    * Origem: **R5** (Relacionamento ternário ``gera_scout`` entre **ATLETAS**, **PARTIDA** e **TIPO_SCOUT**, com atributo ``quantidade``)

* **SCOUT_POSICAO** (``sigla`` → **TIPO_SCOUT**, ``id_posicao`` → **POSICAO**)
    * Origem: **R5** (Relacionamento N:M ``pontua_para`` entre **TIPO_SCOUT** e **POSICAO**).

---
## 2. Justificativas

1. **IDs da API como Chaves Primárias:** Os identificadores numéricos da fonte de dados (``id_clube``, ``id_atleta``, ``id_posicao``, ``id_situacao``, ``id_partida``) foram adotados como chaves artificiais sequenciais para simplificar o programa de carga idempotente (*ON CONFLICT*) e evitar indices redundantes.
2. **Armazenamento de Valores Derivados:** Optou-se por armazenar ``pontuacao_rodada`` e ``pontuacao_atual`` para preservar o histórico imutável após a consolidação e acelerae consultas de ranking, mantendo a consistencia via gatilho.
3. **Chave Substituta em *``ESCALACAO``*:** Utilizou-se ``id_escalacao`` com restricao  *``UNIQUE(id_tecnico, numero_rodada)``* em vez da chave primária composta para reduzir o tamanho da chave estrangeira em *``ITEM_ESCALACAO``*.
4. **Chave Primária de *``ATLETAS_CLUBE_RODADA``*:** A PK foi definida apenas como (``id_atleta``, ``numero_rodada``), deixando ``id_clube`` como atributo/FK, para garantir estruturalmente que um atleta defenda apenas um clube por rodada.
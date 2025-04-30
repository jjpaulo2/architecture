Title: Integrações com APIs lentas
Date: 2025-04-27 21:00
Lang: pt-br
Tags: db, queue, messagery, api
Authors: João Paulo Carvalho


![Language](https://img.shields.io/badge/Language-PT--BR-green)

## Introdução

Você é desenvolvedor em um time de uma empresa de consultoria financeira. A empresa pretende lançar uma aplicação de controle e recomendação de gastos para contas de bancos. Para tal, será necessário fazer consulta em 3 APIs dos bancos digitais parceiros e uma API interna para classificar os dados para o usuário.

Imagine que a API foi pensada inicialmente da forma a seguir.

<pre class="mermaid">
flowchart BT
    web_page@{ shape: procs, label: "Página web"}
    subgraph Externo
        direction LR
        external_api_1(API externa 1)
        external_api_2(API externa 2)
        external_api_3(API externa 3)
    end
    subgraph Back-end
        direction RL
        api[API]
        classifier_api(API de classificação)
        db[(Banco de dados)]
    end

    style api fill:#0AA

    web_page <-->|Consulta| api
    api <-->|Classifica| classifier_api 
    api <-->|Salva| db
    external_api_1 <-->|Consulta| api
    external_api_2 <-->|Consulta| api
    external_api_3 <-->|Consulta| api
</pre>

Uma página web consulta a sua API numa busca por resultados, mas esta busca depende de 3 consultas em APIs externas, um enrequecimento interno em uma API de classificações, e um registro em banco de dados.

A ordem em que as operações são executadas é mostrada abaixo.

<pre class="mermaid">
sequenceDiagram
    Página web ->> API: Requisição
    activate API
    
    API ->> API Externa 1: Requisição
    activate API Externa 1
    API Externa 1 ->> API: Resposta
    deactivate API Externa 1

    API ->> API Externa 2: Requisição
    activate API Externa 2
    API Externa 2 ->> API: Resposta
    deactivate API Externa 2

    API ->> API Externa 3: Requisição
    activate API Externa 3
    API Externa 3 ->> API: Resposta
    deactivate API Externa 3

    API ->> API de classificação: Requisição
    activate API de classificação
    API de classificação ->> API: Resposta
    deactivate API de classificação

    API ->> Banco de dados: Salvar dados classificados
    activate Banco de dados
    Banco de dados ->> API: Sucesso
    deactivate Banco de dados

    API ->> Página web: Resposta
    deactivate API
</pre>

Abaixo há um exemplo de dados enviados para a nossa API.

```json
{
    "id": "xxx",
    "initialDate": "xx/xx/xxxx",
    "finalDate": "xx/xx/xxxx"
}
```

Abaixo há um exemplo de dados retornados pela nossa API.

```json
{
    "id": "xxx",
    "expenses":
    [
        {
            "categoryId": "xxx",
            "categoryName": "Food",
            "purchaseId": "xxxx",
            "moneySpent": "xxxx",
            "purchaseDate": "xx/xx/xxxx hh:mm:ss"
        }
    ]
}
```

### Problema

- As APIs dos parceiros podem ficar fora do ar e apresentar lentidão, quando isso ocorre o uso completo da solução fica indisponível;
- Para históricos com janela de tempo requisitado grande e/ou com muitas transações o tempo de resposta se torna longo. Isso afeta não só o cliente que faz essa requisição como os outros clientes utilizando a aplicação;
- Consultas feitas ao banco de dados apresentam muita lentidão, dificultando a consulta e análise de dados, bem como atrasando o troubleshooting em algumas situações.


## Solução

A principal ideia por trás da melhoria, é manter as operações demoradas, como escrita em banco e consulta em APIs, fora do tempo de espera do usuário. O endpoint da nossa API que irá interagir com o front-end, apenas consultará os últimos registros do banco de dados, e enviará mensagens para indicar que devem ser feitas novas atualizações.

Dessa forma, os componentes da arquitetura, ficam distribuídos como mostrado abaixo.

<pre class="mermaid">
flowchart TB
    web_page@{ shape: procs, label: "Página web"}
    subgraph Externo
        direction LR
        external_api_1(API externa 1)
        external_api_2(API externa 2)
        external_api_3(API externa 3)
    end
    subgraph Back-end
        direction RL
        api[API]
        classifier_api(API de classificação)
        cache[(Cache)]
        db[(Banco de dados)]
        topic[(Tópico)]
        queue_1[(Fila 1)]
        queue_2[(Fila 2)]
        queue_3[(Fila 3)]
        queue_4[(Fila 4)]
        worker_1(Worker 1)
        worker_2(Worker 2)
        worker_3(Worker 3)
        worker_4(Worker 4)
    end

    style api fill:#0AA

    web_page <-->|Consulta| api
    api <-->|Consulta| db
    api <-->|Consulta| cache
    api -->|Mensagem| topic
    topic -->|Mensagem| queue_1
    topic -->|Mensagem| queue_2
    topic -->|Mensagem| queue_3
    queue_1 -->|Consumidor| worker_1
    queue_2 -->|Consumidor| worker_2
    queue_3 -->|Consumidor| worker_3
    worker_1 --->|Mensagem| queue_4
    worker_2 --->|Mensagem| queue_4
    worker_3 --->|Mensagem| queue_4
    worker_1 <--->|Consulta| external_api_1
    worker_2 <--->|Consulta| external_api_2
    worker_3 <--->|Consulta| external_api_3
    queue_4 -->|Consumidor| worker_4
    worker_4 <-->|Salva novos dados classificados| db
    classifier_api <-->|Consulta| worker_4
</pre>

Em tempo de tela, as operações serão executadas da seguinte forma.

<pre class="mermaid">
sequenceDiagram
    Página web ->> API: Requisição
    activate API
    
    API ->> Cache: Consulta
    activate Cache
    Cache ->> API: Resposta
    deactivate Cache

    API -->> Página web: Resposta em cache

    API ->> Banco de dados: Consulta
    activate Banco de dados
    Banco de dados ->> API: Resposta
    deactivate Banco de dados

    API -->> Tópico: Pedido de atualização

    API ->> Página web: Resposta
    deactivate API
</pre>

O uso de cache é um dos principais elementos que deve nos ajudar a diminuir a sobrecarga de consultas ao banco. Ele também pode ser usado como semáforo para garantir que não haja consultas em excesso às APIs externas, o que poderia derrubar nossos parceiros.

Enquanto o usuário já possui dados em tela, a rotina de atualização estará sendo executada assincronamente. Cada uma das consultas externas, será executada na ordem mostrada abaixo.

<pre class="mermaid">
sequenceDiagram
    Fila de consulta -->> Worker de consulta: Consumo
    Worker de consulta ->> API externa: Requisição
    activate API externa
    API externa ->> Worker de consulta: Resposta
    deactivate API externa

    Worker de consulta ->> Fila de classificação: Mensagem
    Fila de classificação -->> Worker de classificação: Consumo
    Worker de classificação ->> API de classificação: Requisição
    activate API de classificação
    API de classificação ->> Worker de classificação: Resposta
    deactivate API de classificação

    Worker de classificação ->> Banco de dados: Registra novos dados
</pre>

O endpoint, a princípio, pode ser mantido com o mesmo contrato, mas com a adição de paginação. O que de cara, também já deve reduzir os impactos em performance nas consultas ao banco.

Abaixo há um exemplo de dados enviados com paginação para a API.

```json
{
    "id": "xxx",
    "initialDate": "xx/xx/xxxx",
    "finalDate": "xx/xx/xxxx",
    "startItem": 0,
    "maxItems": 50,
}
```

Abaixo há um exemplo de dados retornados paginados pela API.

```json
{
    "id": "xxx",
    "startItem": 0,
    "maxItems": 50,
    "totalItems": 150,
    "expenses":
    [
        {
            "categoryId": "xxx",
            "categoryName": "Food",
            "purchaseId": "xxxx",
            "moneySpent": "xxxx",
            "purchaseDate": "xx/xx/xxxx hh:mm:ss"
        }
    ]
}
```

### Pontos de atenção

- Eu não sobrecarregaria a API com a funcionalidade de autenticação. Ao invés disso, usaria algum API Gateway, como Kong, que já possui essa função embutida. Assim, conseguimos diminuir complexidades de código.
- Caso as APIs externas não possam ser consultadas usando intervalo de tempo, é importante adicionar uma etapa extra nos workers de consulta para validarem no banco de dados se os dados consultados são cadastráveis.
- É importante ter uma estratégia de semáforo, para garantir que as consultas sejam feitas apenas dentro de intervalos de tempo seguros. Assim, podemos evitar que o usuário aperte F5 várias vezes e sobrecarrege nossa infra e a infra das APIs externas.
- Como a arquitetura se tornou complexa, é indispensável montar estratégias de monitoramento para garantir que todas as peças estão funcionando conforme o esperado. Assim, eu recomendo o uso de alguma ferramenta como Grafana, para montar dashboards e alertas de comportamento inesperado.

### Melhorias futuras

- Caso ainda hajam gargalos com o banco de dados, poderiam ser criadas duas intâncias separadas. Uma apenas de leitura e outra apenas de escrita. Com rotinas de atualização constantes.

<script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
    mermaid.initialize({ startOnLoad: true });
</script>
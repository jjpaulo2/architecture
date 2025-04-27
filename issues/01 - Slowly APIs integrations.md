# Integrações com APIs lentas

![Language](https://img.shields.io/badge/Language-PT--BR-green)

| Author | Date | Topics |
|-|-|-|
| @jjpaulo2 | 27-04-2025 | `queue`, `messagery`, `database`, `API`, `monitoring` |

## Introdução

Imagine que você possui o seguinte cenário abaixo.

```mermaid
flowchart LR
    subgraph Externo
        direction RL
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

    external_api_1 <-->|Consulta| api
    external_api_2 <-->|Consulta| api
    external_api_3 <-->|Consulta| api
    classifier_api <-->|Classifica| api
    db <-->|Salva| api
```
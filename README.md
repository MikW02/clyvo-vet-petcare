# Clyvo-vet — PetCare API

API REST de gerenciamento de pets (cadastro de animais, espécies, donos) para a
**Clyvo-vet**. Stack Spring Boot 3 + Java 17 + Oracle Database, empacotada em
contêineres Docker, com script Azure CLI para subir tudo numa VM Linux.

> Repositório do zero, sem dependência de outros projetos.

---

## 1. Arquitetura

![Diagrama de arquitetura](docs/arquitetura.drawio)

Abra `docs/arquitetura.drawio` em [diagrams.net](https://app.diagrams.net) para
ver/editar. O fluxo é:

```
Usuário ──HTTP:8080──▶ Public IP ─▶ NSG ─▶ VM Linux
                                            └─ docker network "clyvo-net"
                                               ├─ clyvo-petcare  (Spring Boot, non-root)
                                               └─ clyvo-oracle   (Oracle Free) ──▶ volume nomeado
                                                                                    clyvo-oracle-data
```

- **API → DB:** JDBC em `clyvo-oracle:1521/XEPDB1` pela rede Docker interna.
- **Externo → API:** porta `8080` aberta no NSG.
- **Externo → DB:** porta `1521` opcionalmente aberta (útil para SQL Developer).

---

## 2. Estrutura do repositório

```
challenge052026/
├── app/                      # Aplicação Spring Boot
│   ├── src/main/java/com/clyvovet/petcare/...
│   ├── src/main/resources/application.properties
│   ├── pom.xml
│   └── Dockerfile            # multi-stage, roda como usuário 'clyvo' (uid 999)
├── oracle/
│   ├── Dockerfile            # Oracle Free + init SQL (sem docker-compose)
│   └── init/01_schema.sql
├── scripts/
│   ├── run-local.sh / .ps1   # sobe a stack local com `docker` puro
│   ├── stop-local.sh
│   ├── azure-deploy.sh       # provisiona VM + sobe containers
│   └── azure-destroy.sh      # apaga TUDO no Azure
├── docs/arquitetura.drawio
└── README.md
```

---

## 3. Endpoints

Base URL: `http://<host>:8080`

| Método | Path                  | Descrição                          |
|--------|-----------------------|------------------------------------|
| GET    | `/`                   | Health / banner                    |
| GET    | `/api/pets`           | Lista todos os pets                |
| GET    | `/api/pets?species=dog` | Filtra por espécie               |
| GET    | `/api/pets/{id}`      | Busca um pet                       |
| POST   | `/api/pets`           | Cadastra um pet                    |
| PUT    | `/api/pets/{id}`      | Atualiza um pet                    |
| DELETE | `/api/pets/{id}`      | Remove um pet                      |

Exemplo de payload:

```json
{
  "name": "Thor",
  "species": "dog",
  "breed": "Husky",
  "age": 3,
  "ownerName": "Carla Mendes"
}
```

---

## 4. Setup local (Docker)

**Pré-requisitos:** Docker Desktop em execução. ~4 GB de RAM livres (Oracle é
faminto).

### Linux / macOS / WSL

```bash
chmod +x scripts/*.sh
./scripts/run-local.sh
```

### Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run-local.ps1
```

O script:

1. Cria a network `clyvo-net` e o volume nomeado `clyvo-oracle-data` (idempotente).
2. Builda `clyvo/oracle:local` e `clyvo/petcare:local`.
3. Sobe `clyvo-oracle` em `-d` com o volume montado em `/opt/oracle/oradata`.
4. Espera o healthcheck do Oracle ficar `healthy` (~2 min no 1º boot).
5. Sobe `clyvo-petcare` em `-d`, ligado ao mesmo network, **sem privilégios de root**
   (USER `clyvo` declarado no Dockerfile).

### Testar (CRUD real no Oracle)

```bash
# 1) listar (vem com 3 seeds do init SQL)
curl http://localhost:8080/api/pets

# 2) inserir
curl -X POST http://localhost:8080/api/pets \
     -H 'Content-Type: application/json' \
     -d '{"name":"Thor","species":"dog","breed":"Husky","age":3,"ownerName":"Carla"}'

# 3) ler pelo id
curl http://localhost:8080/api/pets/4

# 4) atualizar
curl -X PUT http://localhost:8080/api/pets/4 \
     -H 'Content-Type: application/json' \
     -d '{"name":"Thor","species":"dog","breed":"Husky","age":4,"ownerName":"Carla"}'

# 5) deletar
curl -X DELETE http://localhost:8080/api/pets/4
```

Provando que persiste no Oracle (não em memória), entre na VM do banco:

```bash
docker exec -it clyvo-oracle sqlplus clyvo/clyvo123@//localhost:1521/XEPDB1
```

Por padrão o sqlplus quebra cada coluna em uma linha (ilegível no terminal
estreito do Windows). Cole o snippet abaixo logo após conectar pra ver as
linhas formatadas em grid:

```sql
SET LINESIZE 200
SET PAGESIZE 50
COL ID         FORMAT 9999
COL NAME       FORMAT A12
COL SPECIES    FORMAT A8
COL BREED      FORMAT A12
COL AGE        FORMAT 999
COL OWNER_NAME FORMAT A18

SELECT * FROM PETS;
```

Saída esperada (depois do seed automático do `DataSeeder`):

```
  ID NAME         SPECIES  BREED         AGE OWNER_NAME
---- ------------ -------- ------------ ---- ------------------
   1 Rex          dog      Labrador        4 Maria Silva
   2 Mia          cat      Siamese         3 Joao Souza
   3 Biscoito     rabbit                   2 Ana Lima
   4 Thor         dog      Husky           5 Carla Mendes
   5 Luna         cat      Persian         1 Pedro Rocha
```

> Pra UI mais confortável (grid, edição inline, autocomplete), use o
> **DBeaver Community** — basta apontar pra `localhost:1521`, service name
> `XEPDB1`, usuário `clyvo` / `clyvo123`.

### Parar / limpar

```bash
./scripts/stop-local.sh           # para containers, mantém volume (dados)
./scripts/stop-local.sh --purge   # para containers E apaga volume + network
```

> **Nota sobre erro `input/output error` no Docker Desktop:** se aparecer
> `write /var/lib/desktop-containerd/...meta.db: input/output error` na hora de
> buildar, é o backend containerd do Docker Desktop em estado ruim — não é o
> Dockerfile. Reinicie o Docker Desktop (ícone na bandeja → *Restart*) e
> rode o script de novo. Verifiquei a imagem da app construindo com sucesso
> (`uid=999(clyvo)`, jar de 52 MB no lugar correto).

---

## 5. Deploy no Azure

**Pré-requisitos:** `az` CLI instalado e logado (`az login`) numa assinatura
com permissão de criar Resource Group + VM.

```bash
# (opcional) ajustar defaults via env vars:
export RG_NAME=rg-clyvo-vet
export LOCATION=brazilsouth
export VM_SIZE=Standard_B2s
export REPO_URL=https://github.com/seu-usuario/clyvo-vet-petcare.git

chmod +x scripts/azure-deploy.sh
./scripts/azure-deploy.sh
```

O que o script faz, de cabo a rabo:

1. Cria o resource group `rg-clyvo-vet`.
2. Cria a VM Ubuntu 22.04 (`Standard_B2s`) com **cloud-init** que já instala
   `docker-ce`, `git`, `nano`, `curl`, `jq` e adiciona o admin user ao grupo
   `docker`.
3. Cria regras de NSG abrindo **8080** (app) e **1521** (Oracle). SSH já vem
   aberto pelo `az vm create`.
4. Espera o cloud-init terminar (`cloud-init status --wait`).
5. Via `az vm run-command`: clona o repo na VM, builda as duas imagens, sobe
   `clyvo-oracle` + `clyvo-petcare` em `-d`, conectados pela `clyvo-net`, com
   o volume nomeado `clyvo-oracle-data` persistindo o banco.

No fim ele imprime o IP público e exemplos de `curl` para testar **de fora**
da VM:

```bash
curl http://<PUBLIC_IP>:8080/api/pets

curl -X POST http://<PUBLIC_IP>:8080/api/pets \
     -H 'Content-Type: application/json' \
     -d '{"name":"Luna","species":"cat","breed":"Persa","age":2,"ownerName":"Pedro"}'
```

### Variáveis suportadas pelo deploy

| Variável             | Default                | O que é                              |
|----------------------|------------------------|--------------------------------------|
| `RG_NAME`            | `rg-clyvo-vet`         | Resource Group                       |
| `LOCATION`           | `brazilsouth`          | Região Azure                         |
| `VM_NAME`            | `vm-clyvo-vet`         | Nome da VM                           |
| `VM_SIZE`            | `Standard_B2s`         | SKU                                  |
| `ADMIN_USER`         | `clyvoadmin`           | Usuário Linux                        |
| `APP_PORT`           | `8080`                 | Porta exposta da API                 |
| `DB_PORT`            | `1521`                 | Porta exposta do Oracle              |
| `ORACLE_PASSWORD`    | `oracle123`            | Senha do `SYSTEM`                    |
| `APP_USER`           | `clyvo`                | Schema/usuário da aplicação          |
| `APP_USER_PASSWORD`  | `clyvo123`             | Senha do schema                      |
| `REPO_URL`           | placeholder            | Repo Git que a VM vai clonar         |

> **Importante:** as senhas default são para fins de demonstração. Em produção,
> sobrescreva tudo via env vars antes de rodar.

---

## 6. Limpeza — DELETAR a VM Azure

Para apagar **tudo** que foi criado (VM, disco, NIC, IP público, NSG,
resource group):

```bash
./scripts/azure-destroy.sh
```

ou, manualmente, em um único comando:

```bash
az group delete --name rg-clyvo-vet --yes --no-wait
```

Para confirmar que sumiu:

```bash
az group exists --name rg-clyvo-vet   # deve retornar "false"
```

Para limpar a stack local sem mexer no Azure:

```bash
./scripts/stop-local.sh --purge
docker image rm clyvo/petcare:local clyvo/oracle:local
```

---

## 7. Configuração da aplicação

Tudo é via env var (12-factor). Defaults em `application.properties`:

| Env             | Default                                                     |
|-----------------|-------------------------------------------------------------|
| `SERVER_PORT`   | `8080`                                                      |
| `DB_URL`        | `jdbc:oracle:thin:@localhost:1521/XEPDB1`                 |
| `DB_USER`       | `clyvo`                                                     |
| `DB_PASSWORD`   | `clyvo123`                                                  |

O Hibernate roda com `ddl-auto=update`, então a tabela `PETS` é criada
automaticamente no 1º start. O `oracle/init/01_schema.sql` ainda cria a tabela
de forma idempotente e popula 3 pets de exemplo na 1ª subida do banco.

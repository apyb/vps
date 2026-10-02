# VPS — Scripts de Setup e Configuração

Repositório com scripts de automação e arquivos de configuração usados no servidor VPS da APyB para hospedar o [Pretix](https://pretix.eu) (sistema de venda de ingressos).

---

## Visão Geral

O repositório está organizado em duas partes:

- **Scripts de setup** (`*.sh`): automatizam a configuração e o hardening do servidor
- **Arquivos de configuração** (`etc/`): arquivos prontos para serem copiados para o servidor

---

## Pré-requisitos

- Servidor Ubuntu 26.04 LTS (acesso root)
- Chave SSH pública disponível
- Banco de dados PostgreSQL provisionado (ex: AWS RDS)

---

## Ordem de Execução dos Scripts

Execute os scripts **como root** na seguinte ordem:

### 1. `setup.sh` — Setup Base e Hardening do VPS

Prepara o servidor do zero:
- Atualiza o sistema e instala pacotes essenciais (ufw, fail2ban, Docker, Nginx, Redis, Certbot, etc.)
- Habilita atualizações automáticas de segurança
- Cria o usuário `apyb` com privilégios sudo
- Configura autenticação por chave SSH (desabilita senha)
- Configura o firewall UFW (portas: SSH customizada, 80 e 443)

**Antes de executar**, edite as variáveis no topo do script:
```bash
PUBKEY="sua_chave_ssh_publica_aqui"
SSH_PORT="22022"  # Porta SSH customizada
```

```bash
bash setup.sh
```

---

### 2. `setup_pretix.sh` — Setup do Ambiente Pretix

Configura o ambiente necessário para rodar o Pretix:
- Cria os diretórios `/var/pretix-data` e `/etc/pretix` com as permissões corretas
- Configura o Redis com socket Unix
- Cria um cron job para tarefas periódicas do Pretix
- Baixa a imagem oficial `pretix/standalone:stable`
- Constrói a imagem customizada `pretix-apyb:latest` a partir do `Dockerfile` em `/etc/pretix/`

> **Antes de executar**, copie os arquivos de `etc/` para o servidor (veja a seção abaixo).

```bash
bash setup_pretix.sh
```

---

### 3. `setup_ssl.sh` — Configuração do SSL com Certbot

Configura o HTTPS via Let's Encrypt:
- Remove a configuração padrão do Nginx
- Cria uma configuração temporária HTTP para validação do domínio
- Emite o certificado SSL via Certbot (plugin Nginx)
- Substitui pela configuração real do Pretix com HTTPS
- Habilita a renovação automática do certificado

> **Pré-requisito**: o arquivo de configuração Nginx real deve estar em `/home/apyb/pretix` antes de executar. Use `etc/nginx/sites-available/pretix` como referência.

```bash
bash setup_ssl.sh
```

---

## Arquivos de Configuração (`etc/`)

Estes arquivos devem ser copiados para o servidor antes de executar os scripts de setup:

| Arquivo | Destino no servidor | Descrição |
|---|---|---|
| `etc/pretix/pretix.cfg` | `/etc/pretix/pretix.cfg` | Configuração principal do Pretix (banco, e-mail, Redis) |
| `etc/pretix/Dockerfile` | `/etc/pretix/Dockerfile` | Imagem Docker customizada com suporte ao PT-BR |
| `etc/nginx/sites-available/pretix` | `/home/apyb/pretix` | Configuração Nginx com proxy reverso e SSL |
| `etc/redis/redis.conf` | Adicionado ao `/etc/redis/redis.conf` | Configuração do socket Unix do Redis |
| `etc/systemd/system/pretix.service` | `/etc/systemd/system/pretix.service` | Serviço systemd para o container Docker do Pretix |

### Configurações a personalizar em `pretix.cfg`

```ini
[database]
password=SENHA_DO_BANCO
host=seu-host-de-banco.rds.amazonaws.com

[mail]
user=SEU_USUARIO@smtp-brevo.com
password=SENHA_DO_SMTP
```

### Ativando o serviço do Pretix

Após copiar o `pretix.service` e executar os scripts de setup:

```bash
systemctl daemon-reload
systemctl enable --now pretix.service
```

# Quiz TI - Aplicação de Quiz em Tecnologia da Informação

Uma aplicação web gamificada para testar conhecimentos em TI, desenvolvida com Flask e MySQL.

## 🚀 Funcionalidades

- Sistema de autenticação de usuários
- Quiz com múltiplas categorias e níveis de dificuldade
- Sistema de pontuação e níveis
- Ranking global e por categoria
- Conquistas e badges
- Painel administrativo

## 🛠️ Tecnologias

- **Backend**: Python 3.8+, Flask
- **Frontend**: HTML5, CSS3, JavaScript, Tailwind CSS
- **Banco de Dados**: MySQL
- **Autenticação**: JWT (JSON Web Tokens)

## 📋 Pré-requisitos

- Python 3.8 ou superior
- MySQL 8.0 ou superior
- pip (gerenciador de pacotes Python)

## 🔧 Instalação

1. Clone o repositório:
```bash
git clone https://github.com/seu-usuario/quiz-ti.git
cd quiz-ti
```

2. Crie um ambiente virtual:
```bash
python -m venv venv
source venv/bin/activate  # Linux/Mac
venv\Scripts\activate     # Windows
```

3. Instale as dependências:
```bash
pip install -r requirements.txt
```

4. Configure o banco de dados:
- Crie um banco de dados MySQL
- Execute o script `database.sql`
- Configure as variáveis de ambiente no arquivo `.env`

5. Execute a aplicação:
```bash
python app.py
```

## 📝 Estrutura do Projeto

```
quiz-ti/
├── app.py              # Aplicação principal
├── config.py           # Configurações
├── requirements.txt    # Dependências
├── database.sql        # Script do banco de dados
├── .env                # Variáveis de ambiente
└── templates/          # Templates HTML
    ├── base.html
    ├── index.html
    ├── login.html
    ├── register.html
    ├── dashboard.html
    ├── quiz.html
    └── results.html
```

## 🔒 Variáveis de Ambiente

Crie um arquivo `.env` com as seguintes variáveis:

```env
SECRET_KEY=sua_chave_secreta_aqui
DEBUG=True

# Configurações do MySQL
MYSQL_HOST=localhost
MYSQL_USER=root
MYSQL_PASSWORD=
MYSQL_DB=quiz_ti

# Configurações da aplicação
QUESTIONS_PER_QUIZ=10
ENABLE_TIMER=True
CONSECUTIVE_BONUS_THRESHOLD=3
CONSECUTIVE_BONUS_PERCENTAGE=10
TIME_BONUS_PERCENTAGE=20
TIME_BONUS_THRESHOLD=50
PARTIAL_MATCH_ENABLED=True
RANKING_LIMIT=10

# Configurações de e-mail
MAIL_SERVER=smtp.gmail.com
MAIL_PORT=587
MAIL_USE_TLS=True
MAIL_USERNAME=seu_email@gmail.com
MAIL_PASSWORD=sua_senha_de_app
MAIL_DEFAULT_SENDER=seu_email@gmail.com
```

## 📊 Status do Projeto

### Implementado ✅
- [x] Sistema de autenticação
- [x] Interface base com Tailwind CSS
- [x] Páginas de login e registro
- [x] Dashboard do usuário
- [x] Sistema de quiz
- [x] Página de resultados

### Em Desenvolvimento 🚧
- [ ] Sistema de conquistas
- [ ] Ranking global
- [ ] Painel administrativo
- [ ] Recuperação de senha
- [ ] Testes automatizados

## 🤝 Contribuição

1. Faça um fork do projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## 📧 Contato

Seu Nome - [@seu_twitter](https://twitter.com/seu_twitter) - email@exemplo.com

Link do Projeto: [https://github.com/seu-usuario/quiz-ti](https://github.com/seu-usuario/quiz-ti) 
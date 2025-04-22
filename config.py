import os
from dotenv import load_dotenv

# Carrega as variáveis de ambiente do arquivo .env
load_dotenv()

class Config:
    # Configurações do Flask
    SECRET_KEY = os.getenv('SECRET_KEY', 'sua_chave_secreta_aqui')
    DEBUG = os.getenv('DEBUG', 'True') == 'True'
    
    # Configurações do MySQL
    MYSQL_HOST = os.getenv('MYSQL_HOST', 'localhost')
    MYSQL_USER = os.getenv('MYSQL_USER', 'root')
    MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', '')
    MYSQL_DB = os.getenv('MYSQL_DB', 'quiz_ti')
    
    # Configurações da aplicação
    QUESTIONS_PER_QUIZ = int(os.getenv('QUESTIONS_PER_QUIZ', '10'))
    ENABLE_TIMER = os.getenv('ENABLE_TIMER', 'True') == 'True'
    CONSECUTIVE_BONUS_THRESHOLD = int(os.getenv('CONSECUTIVE_BONUS_THRESHOLD', '3'))
    CONSECUTIVE_BONUS_PERCENTAGE = int(os.getenv('CONSECUTIVE_BONUS_PERCENTAGE', '10'))
    TIME_BONUS_PERCENTAGE = int(os.getenv('TIME_BONUS_PERCENTAGE', '20'))
    TIME_BONUS_THRESHOLD = int(os.getenv('TIME_BONUS_THRESHOLD', '50'))
    PARTIAL_MATCH_ENABLED = os.getenv('PARTIAL_MATCH_ENABLED', 'True') == 'True'
    RANKING_LIMIT = int(os.getenv('RANKING_LIMIT', '10'))
    
    # Configurações de e-mail (para recuperação de senha)
    MAIL_SERVER = os.getenv('MAIL_SERVER', 'smtp.gmail.com')
    MAIL_PORT = int(os.getenv('MAIL_PORT', '587'))
    MAIL_USE_TLS = os.getenv('MAIL_USE_TLS', 'True') == 'True'
    MAIL_USERNAME = os.getenv('MAIL_USERNAME', '')
    MAIL_PASSWORD = os.getenv('MAIL_PASSWORD', '')
    MAIL_DEFAULT_SENDER = os.getenv('MAIL_DEFAULT_SENDER', '') 
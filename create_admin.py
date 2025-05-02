import bcrypt

# Dados do administrador
admin_email = 'admin@quizti.com'
admin_password = 'admin123'  # Você deve alterar esta senha em produção!
admin_name = 'Administrador'

# Gerar hash da senha
password_hash = bcrypt.hashpw(admin_password.encode('utf-8'), bcrypt.gensalt())

# Imprimir o comando SQL
print("\n=== Comando SQL para criar o administrador ===\n")
print(f"""INSERT INTO users (name, email, password_hash, is_admin, is_active) VALUES 
('{admin_name}', '{admin_email}', '{password_hash.decode('utf-8')}', TRUE, TRUE);""") 
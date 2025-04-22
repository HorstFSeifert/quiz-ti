from flask import Flask, render_template, request, redirect, url_for, flash, session, jsonify
from flask_mail import Mail, Message
import mysql.connector
from mysql.connector import Error
from config import Config
import bcrypt
import os
import random
import time
from datetime import datetime, timedelta
import jwt
from functools import wraps

app = Flask(__name__)
app.config.from_object(Config)
mail = Mail(app)

# Decorator para verificar se o usuário está logado
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            flash('Por favor, faça login para acessar esta página.', 'warning')
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

# Decorator para verificar se o usuário é administrador
def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session or not session.get('is_admin'):
            flash('Acesso restrito a administradores.', 'danger')
            return redirect(url_for('index'))
        return f(*args, **kwargs)
    return decorated_function

# Função para conectar ao banco de dados
def get_db_connection():
    try:
        connection = mysql.connector.connect(
            host=app.config['MYSQL_HOST'],
            user=app.config['MYSQL_USER'],
            password=app.config['MYSQL_PASSWORD'],
            database=app.config['MYSQL_DB']
        )
        return connection
    except Error as e:
        print(f"Erro ao conectar ao MySQL: {e}")
        return None

# Rotas da aplicação
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        name = request.form['name']
        email = request.form['email']
        password = request.form['password']
        
        # Verifica se o e-mail já está cadastrado
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
        if cursor.fetchone():
            flash('Este e-mail já está cadastrado.', 'danger')
            return redirect(url_for('register'))
        
        # Criptografa a senha
        hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
        
        # Insere o novo usuário
        cursor.execute(
            "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s)",
            (name, email, hashed_password)
        )
        conn.commit()
        cursor.close()
        conn.close()
        
        flash('Cadastro realizado com sucesso! Faça login para continuar.', 'success')
        return redirect(url_for('login'))
    
    return render_template('register.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        email = request.form['email']
        password = request.form['password']
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
        user = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if user and bcrypt.checkpw(password.encode('utf-8'), user['password_hash'].encode('utf-8')):
            session['user_id'] = user['user_id']
            session['name'] = user['name']
            session['is_admin'] = user['is_admin']
            flash('Login realizado com sucesso!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('E-mail ou senha incorretos.', 'danger')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    flash('Logout realizado com sucesso!', 'success')
    return redirect(url_for('index'))

@app.route('/dashboard')
@login_required
def dashboard():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obtém estatísticas do usuário
    cursor.execute("""
        SELECT 
            u.total_points,
            u.current_level,
            l.level_name,
            COUNT(DISTINCT ub.badge_id) AS badges_count
        FROM users u
        LEFT JOIN levels l ON u.current_level = l.level_id
        LEFT JOIN user_badges ub ON u.user_id = ub.user_id
        WHERE u.user_id = %s
        GROUP BY u.user_id
    """, (session['user_id'],))
    stats = cursor.fetchone()
    
    # Obtém categorias disponíveis
    cursor.execute("SELECT * FROM categories")
    categories = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('dashboard.html', stats=stats, categories=categories)

@app.route('/quiz/<int:category_id>/<int:difficulty_id>')
@login_required
def start_quiz(category_id, difficulty_id):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obtém perguntas aleatórias
    cursor.execute("""
        SELECT q.*, qt.name as question_type
        FROM questions q
        JOIN question_types qt ON q.type_id = qt.type_id
        WHERE q.category_id = %s AND q.difficulty_id = %s AND q.is_active = TRUE
        ORDER BY RAND()
        LIMIT %s
    """, (category_id, difficulty_id, app.config['QUESTIONS_PER_QUIZ']))
    questions = cursor.fetchall()
    
    # Para cada pergunta, obtém as alternativas (se for múltipla escolha)
    for question in questions:
        if question['type_id'] == 1:  # Múltipla escolha
            cursor.execute("""
                SELECT * FROM alternatives
                WHERE question_id = %s
                ORDER BY RAND()
            """, (question['question_id'],))
            question['alternatives'] = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('quiz.html', questions=questions)

@app.route('/submit_quiz', methods=['POST'])
@login_required
def submit_quiz():
    data = request.get_json()
    answers = data.get('answers', [])
    
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Inicia uma nova sessão de quiz
    cursor.execute("""
        INSERT INTO quiz_sessions (user_id, category_id, difficulty_id)
        VALUES (%s, %s, %s)
    """, (session['user_id'], data['category_id'], data['difficulty_id']))
    session_id = cursor.lastrowid
    
    total_points = 0
    correct_answers = 0
    
    # Processa cada resposta
    for answer in answers:
        question_id = answer['question_id']
        response_time = answer.get('response_time')
        
        if answer['type'] == 'multiple_choice':
            cursor.execute("""
                INSERT INTO user_answers 
                (session_id, question_id, alternative_id, response_time)
                VALUES (%s, %s, %s, %s)
            """, (session_id, question_id, answer['answer'], response_time))
        else:  # Resposta escrita
            cursor.execute("""
                INSERT INTO user_answers 
                (session_id, question_id, written_response, response_time)
                VALUES (%s, %s, %s, %s)
            """, (session_id, question_id, answer['answer'], response_time))
        
        # Verifica se a resposta está correta
        cursor.execute("""
            SELECT is_correct, points_earned 
            FROM user_answers 
            WHERE answer_id = LAST_INSERT_ID()
        """)
        result = cursor.fetchone()
        
        if result['is_correct']:
            correct_answers += 1
            total_points += result['points_earned']
    
    # Atualiza a sessão do quiz
    accuracy = (correct_answers / len(answers)) * 100
    cursor.execute("""
        UPDATE quiz_sessions 
        SET completed = TRUE, 
            total_points = %s,
            accuracy_percentage = %s
        WHERE session_id = %s
    """, (total_points, accuracy, session_id))
    
    conn.commit()
    cursor.close()
    conn.close()
    
    return jsonify({
        'success': True,
        'total_points': total_points,
        'correct_answers': correct_answers,
        'accuracy': accuracy
    })

@app.route('/ranking')
def ranking():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obtém ranking global
    cursor.execute("""
        SELECT 
            u.name,
            u.total_points,
            l.level_name,
            COUNT(DISTINCT ub.badge_id) AS badges_count
        FROM users u
        LEFT JOIN levels l ON u.current_level = l.level_id
        LEFT JOIN user_badges ub ON u.user_id = ub.user_id
        WHERE u.is_active = TRUE
        GROUP BY u.user_id
        ORDER BY u.total_points DESC
        LIMIT %s
    """, (app.config['RANKING_LIMIT'],))
    global_ranking = cursor.fetchall()
    
    # Obtém categorias para filtro
    cursor.execute("SELECT * FROM categories")
    categories = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('ranking.html', 
                         global_ranking=global_ranking,
                         categories=categories)

@app.route('/profile')
@login_required
def profile():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obtém informações do usuário
    cursor.execute("""
        SELECT 
            u.*,
            l.level_name,
            COUNT(DISTINCT ub.badge_id) AS badges_count
        FROM users u
        LEFT JOIN levels l ON u.current_level = l.level_id
        LEFT JOIN user_badges ub ON u.user_id = ub.user_id
        WHERE u.user_id = %s
        GROUP BY u.user_id
    """, (session['user_id'],))
    user_info = cursor.fetchone()
    
    # Obtém badges do usuário
    cursor.execute("""
        SELECT b.*, ub.earned_at
        FROM badges b
        JOIN user_badges ub ON b.badge_id = ub.badge_id
        WHERE ub.user_id = %s
        ORDER BY ub.earned_at DESC
    """, (session['user_id'],))
    badges = cursor.fetchall()
    
    # Obtém estatísticas por categoria
    cursor.execute("""
        SELECT 
            c.name,
            uc.points,
            uc.questions_answered,
            uc.correct_answers,
            ROUND((uc.correct_answers / uc.questions_answered) * 100, 2) AS accuracy
        FROM user_categories uc
        JOIN categories c ON uc.category_id = c.category_id
        WHERE uc.user_id = %s
        ORDER BY uc.points DESC
    """, (session['user_id'],))
    category_stats = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('profile.html',
                         user_info=user_info,
                         badges=badges,
                         category_stats=category_stats)

# Rotas administrativas
@app.route('/admin')
@admin_required
def admin_dashboard():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obtém estatísticas gerais
    cursor.execute("""
        SELECT 
            COUNT(*) AS total_users,
            SUM(total_points) AS total_points,
            AVG(accuracy_percentage) AS avg_accuracy
        FROM users u
        LEFT JOIN quiz_sessions qs ON u.user_id = qs.user_id
        WHERE u.is_active = TRUE
    """)
    stats = cursor.fetchone()
    
    # Obtém perguntas mais erradas
    cursor.execute("""
        SELECT 
            q.content,
            c.name AS category,
            COUNT(ua.answer_id) AS total_attempts,
            SUM(IF(ua.is_correct = FALSE, 1, 0)) AS incorrect_attempts,
            ROUND((SUM(IF(ua.is_correct = FALSE, 1, 0)) / COUNT(ua.answer_id)) * 100, 2) AS failure_rate
        FROM questions q
        JOIN user_answers ua ON q.question_id = ua.question_id
        JOIN categories c ON q.category_id = c.category_id
        GROUP BY q.question_id
        HAVING total_attempts >= 5
        ORDER BY failure_rate DESC
        LIMIT 10
    """)
    failed_questions = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('admin/dashboard.html',
                         stats=stats,
                         failed_questions=failed_questions)

@app.route('/admin/questions', methods=['GET', 'POST'])
@admin_required
def manage_questions():
    if request.method == 'POST':
        content = request.form['content']
        category_id = request.form['category_id']
        difficulty_id = request.form['difficulty_id']
        type_id = request.form['type_id']
        base_points = request.form['base_points']
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Insere a nova pergunta
        cursor.execute("""
            INSERT INTO questions 
            (content, category_id, difficulty_id, type_id, base_points, created_by)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (content, category_id, difficulty_id, type_id, base_points, session['user_id']))
        
        question_id = cursor.lastrowid
        
        # Se for múltipla escolha, insere as alternativas
        if type_id == 1:
            alternatives = request.form.getlist('alternatives[]')
            correct_index = int(request.form['correct_alternative'])
            
            for i, alternative in enumerate(alternatives):
                cursor.execute("""
                    INSERT INTO alternatives 
                    (question_id, content, is_correct)
                    VALUES (%s, %s, %s)
                """, (question_id, alternative, i == correct_index))
        
        # Se for resposta escrita, insere a resposta correta
        elif type_id == 2:
            correct_answer = request.form['correct_answer']
            alternative_answers = request.form.get('alternative_answers', '')
            
            cursor.execute("""
                INSERT INTO written_answers 
                (question_id, correct_answer, alternative_answers)
                VALUES (%s, %s, %s)
            """, (question_id, correct_answer, alternative_answers))
        
        conn.commit()
        cursor.close()
        conn.close()
        
        flash('Pergunta adicionada com sucesso!', 'success')
        return redirect(url_for('manage_questions'))
    
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obtém categorias e dificuldades
    cursor.execute("SELECT * FROM categories")
    categories = cursor.fetchall()
    
    cursor.execute("SELECT * FROM difficulties")
    difficulties = cursor.fetchall()
    
    cursor.execute("SELECT * FROM question_types")
    question_types = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('admin/questions.html',
                         categories=categories,
                         difficulties=difficulties,
                         question_types=question_types)

@app.route('/admin/users')
@admin_required
def manage_users():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    cursor.execute("""
        SELECT 
            u.*,
            l.level_name,
            COUNT(DISTINCT ub.badge_id) AS badges_count
        FROM users u
        LEFT JOIN levels l ON u.current_level = l.level_id
        LEFT JOIN user_badges ub ON u.user_id = ub.user_id
        GROUP BY u.user_id
        ORDER BY u.created_at DESC
    """)
    users = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('admin/users.html', users=users)

# API para recuperação de senha
@app.route('/forgot_password', methods=['GET', 'POST'])
def forgot_password():
    if request.method == 'POST':
        email = request.form['email']
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
        user = cursor.fetchone()
        
        if user:
            # Gera token de redefinição
            token = jwt.encode(
                {
                    'user_id': user['user_id'],
                    'exp': datetime.utcnow() + timedelta(hours=1)
                },
                app.config['SECRET_KEY'],
                algorithm='HS256'
            )
            
            # Atualiza token no banco
            cursor.execute("""
                UPDATE users 
                SET reset_token = %s,
                    reset_token_expires = DATE_ADD(NOW(), INTERVAL 1 HOUR)
                WHERE user_id = %s
            """, (token, user['user_id']))
            
            conn.commit()
            
            # Envia e-mail
            msg = Message(
                'Redefinição de Senha - Quiz TI',
                sender=app.config['MAIL_DEFAULT_SENDER'],
                recipients=[email]
            )
            msg.body = f"""
            Olá {user['name']},
            
            Para redefinir sua senha, clique no link abaixo:
            {url_for('reset_password', token=token, _external=True)}
            
            Este link expira em 1 hora.
            
            Se você não solicitou esta redefinição, ignore este e-mail.
            """
            mail.send(msg)
        
        flash('Se o e-mail estiver cadastrado, você receberá instruções para redefinir sua senha.', 'info')
        return redirect(url_for('login'))
    
    return render_template('forgot_password.html')

@app.route('/reset_password/<token>', methods=['GET', 'POST'])
def reset_password(token):
    try:
        payload = jwt.decode(token, app.config['SECRET_KEY'], algorithms=['HS256'])
        user_id = payload['user_id']
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("""
            SELECT * FROM users 
            WHERE user_id = %s 
            AND reset_token = %s 
            AND reset_token_expires > NOW()
        """, (user_id, token))
        user = cursor.fetchone()
        
        if not user:
            flash('Link inválido ou expirado.', 'danger')
            return redirect(url_for('forgot_password'))
        
        if request.method == 'POST':
            password = request.form['password']
            confirm_password = request.form['confirm_password']
            
            if password != confirm_password:
                flash('As senhas não coincidem.', 'danger')
                return redirect(url_for('reset_password', token=token))
            
            # Atualiza a senha
            hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
            cursor.execute("""
                UPDATE users 
                SET password_hash = %s,
                    reset_token = NULL,
                    reset_token_expires = NULL
                WHERE user_id = %s
            """, (hashed_password, user_id))
            
            conn.commit()
            cursor.close()
            conn.close()
            
            flash('Senha redefinida com sucesso! Faça login com sua nova senha.', 'success')
            return redirect(url_for('login'))
        
        return render_template('reset_password.html', token=token)
        
    except jwt.ExpiredSignatureError:
        flash('Link expirado. Solicite uma nova redefinição de senha.', 'danger')
        return redirect(url_for('forgot_password'))
    except jwt.InvalidTokenError:
        flash('Link inválido.', 'danger')
        return redirect(url_for('forgot_password'))

if __name__ == '__main__':
    app.run(debug=True) 
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
import io
import csv

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
    
    try:
        # Primeiro, verificar se existem questões não respondidas
        cursor.execute("""
            SELECT COUNT(*) as available_questions
            FROM questions q
            WHERE q.category_id = %s 
            AND q.difficulty_id = %s 
            AND q.is_active = TRUE
            AND NOT EXISTS (
                -- Verificar se o usuário já respondeu esta questão em qualquer sessão
                SELECT 1 
                FROM user_answers ua
                JOIN quiz_sessions qs ON ua.session_id = qs.session_id
                WHERE qs.user_id = %s
                AND ua.question_id = q.question_id
            )
        """, (category_id, difficulty_id, session['user_id']))
        
        result = cursor.fetchone()
        
        if result['available_questions'] == 0:
            # Obter nomes da categoria e dificuldade para a mensagem
            cursor.execute("""
                SELECT c.name as category_name, d.name as difficulty_name
                FROM categories c, difficulties d
                WHERE c.category_id = %s AND d.difficulty_id = %s
            """, (category_id, difficulty_id))
            
            names = cursor.fetchone()
            flash(f'Parabéns! Você já completou todas as questões da categoria {names["category_name"]} '
                  f'com dificuldade {names["difficulty_name"]}!', 'success')
            return redirect(url_for('dashboard'))

        # Se existem questões disponíveis, obter uma aleatória que não foi respondida
        cursor.execute("""
            SELECT 
                q.question_id, 
                q.content, 
                q.type_id, 
                q.base_points,
                d.time_limit,
                qf.correct_feedback,
                qf.incorrect_feedback
            FROM questions q
            JOIN difficulties d ON q.difficulty_id = d.difficulty_id
            LEFT JOIN question_feedback qf ON q.question_id = qf.question_id
            WHERE q.category_id = %s
            AND q.difficulty_id = %s
            AND q.is_active = TRUE
            AND NOT EXISTS (
                -- Verificar se o usuário já respondeu esta questão
                SELECT 1 
                FROM user_answers ua
                JOIN quiz_sessions qs ON ua.session_id = qs.session_id
                WHERE qs.user_id = %s
                AND ua.question_id = q.question_id
            )
            ORDER BY RAND()
            LIMIT 1
        """, (category_id, difficulty_id, session['user_id']))
        
        question = cursor.fetchone()
        
        # Obter informações da categoria e dificuldade
        cursor.execute("""
            SELECT c.name as category_name, d.name as difficulty_name
            FROM categories c, difficulties d
            WHERE c.category_id = %s AND d.difficulty_id = %s
        """, (category_id, difficulty_id))
        quiz_info = cursor.fetchone()
        quiz_info['time_limit'] = question['time_limit']
        
        # Se for múltipla escolha, obter alternativas
        if question['type_id'] == 1:
            cursor.execute("""
                SELECT alternative_id, content
                FROM alternatives
                WHERE question_id = %s
                ORDER BY RAND()
            """, (question['question_id'],))
            question['alternatives'] = cursor.fetchall()
        
        # Criar nova sessão
        cursor.execute("""
            INSERT INTO quiz_sessions 
            (user_id, category_id, difficulty_id, start_time)
            VALUES (%s, %s, %s, NOW())
        """, (session['user_id'], category_id, difficulty_id))
        
        session_id = cursor.lastrowid
        conn.commit()
        
        return render_template('quiz.html',
                             question=question,
                             quiz_info=quiz_info,
                             session_id=session_id)
                             
    except Exception as e:
        conn.rollback()
        flash(f'Erro ao carregar questão: {str(e)}', 'danger')
        return redirect(url_for('dashboard'))
        
    finally:
        cursor.close()
        conn.close()

@app.route('/quiz/submit', methods=['POST'])
@login_required
def submit_quiz():
    if not request.is_json:
        return jsonify({'error': 'Requisição deve ser JSON'}), 400
        
    data = request.get_json()
    session_id = data.get('session_id')
    question_id = data.get('question_id')
    answer = data.get('answer')
    response_time = data.get('response_time', 0)
    
    if not all([session_id, question_id, answer]):
        return jsonify({'error': 'Dados incompletos'}), 400
    
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    try:
        # Verificar se a questão pertence à sessão atual
        cursor.execute("""
            SELECT q.type_id, q.category_id, q.difficulty_id,
                   qf.correct_feedback, qf.incorrect_feedback
            FROM questions q
            LEFT JOIN question_feedback qf ON q.question_id = qf.question_id
            JOIN quiz_sessions qs ON qs.session_id = %s
            WHERE q.question_id = %s
            AND qs.category_id = q.category_id
            AND qs.difficulty_id = q.difficulty_id
        """, (session_id, question_id))
        question = cursor.fetchone()
        
        if not question:
            return jsonify({'error': 'Questão inválida'}), 400
        
        # Verificar se a resposta está correta
        is_correct = False
        if question['type_id'] == 1:  # Múltipla escolha
            cursor.execute("""
                SELECT is_correct FROM alternatives
                WHERE alternative_id = %s AND question_id = %s
            """, (answer, question_id))
            result = cursor.fetchone()
            is_correct = result['is_correct'] if result else False
        else:  # Resposta escrita
            cursor.execute("""
                SELECT correct_answer, alternative_answers
                FROM written_answers
                WHERE question_id = %s
            """, (question_id,))
            correct = cursor.fetchone()
            if correct:
                answer_lower = answer.lower().strip()
                correct_answers = [ans.lower().strip() for ans in 
                                 (correct['alternative_answers'] or '').split('|') + 
                                 [correct['correct_answer']]]
                is_correct = answer_lower in correct_answers
        
        # Registrar resposta
        cursor.execute("""
            INSERT INTO user_answers 
            (session_id, question_id, alternative_id, written_response, is_correct, response_time)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (
            session_id,
            question_id,
            answer if question['type_id'] == 1 else None,
            answer if question['type_id'] == 2 else None,
            is_correct,
            response_time
        ))
        
        # Obter próxima categoria e dificuldade para redirecionamento
        category_id = question['category_id']
        difficulty_id = question['difficulty_id']
        
        conn.commit()
        
        return jsonify({
            'success': True,
            'is_correct': is_correct,
            'feedback': question['correct_feedback'] if is_correct else question['incorrect_feedback'],
            'next_url': url_for('start_quiz', category_id=category_id, difficulty_id=difficulty_id)
        })
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
        
    finally:
        cursor.close()
        conn.close()

@app.route('/profile')
@login_required
def profile():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    try:
        # Obter informações do usuário
        cursor.execute("""
            SELECT 
                u.*,
                l.level_name,
                COUNT(DISTINCT ub.badge_id) as badges_count
            FROM users u
            LEFT JOIN levels l ON u.current_level = l.level_id
            LEFT JOIN user_badges ub ON u.user_id = ub.user_id
            WHERE u.user_id = %s
            GROUP BY u.user_id
        """, (session['user_id'],))
        user_info = cursor.fetchone()
        
        # Obter próximo nível e calcular progresso
        cursor.execute("""
            SELECT l.*, 
                   (l.min_points - %s) as points_needed,
                   ROUND(
                       ((%s - COALESCE(
                           (SELECT max_points FROM levels WHERE level_id < l.level_id ORDER BY level_id DESC LIMIT 1),
                           0
                       )) / (l.min_points - COALESCE(
                           (SELECT max_points FROM levels WHERE level_id < l.level_id ORDER BY level_id DESC LIMIT 1),
                           0
                       ))) * 100,
                       1
                   ) as percentage
            FROM levels l
            WHERE l.min_points > %s
            ORDER BY l.min_points
            LIMIT 1
        """, (user_info['total_points'], user_info['total_points'], user_info['total_points']))
        next_level = cursor.fetchone()
        
        if not next_level:
            next_level = {
                'level_name': 'Nível Máximo',
                'points_needed': 0,
                'percentage': 100
            }
        
        # Calcular progresso
        progress = {
            'percentage': next_level['percentage'],
            'points_needed': next_level['points_needed']
        }
        
        # Obter estatísticas por categoria
        cursor.execute("""
            SELECT 
                c.name,
                uc.points,
                uc.questions_answered,
                uc.correct_answers,
                ROUND((uc.correct_answers / NULLIF(uc.questions_answered, 0)) * 100, 2) as accuracy
            FROM user_categories uc
            JOIN categories c ON uc.category_id = c.category_id
            WHERE uc.user_id = %s
            ORDER BY uc.points DESC
        """, (session['user_id'],))
        category_stats = cursor.fetchall()
        
        # Obter badges recentes
        cursor.execute("""
            SELECT b.*, ub.earned_at
            FROM badges b
            JOIN user_badges ub ON b.badge_id = ub.badge_id
            WHERE ub.user_id = %s
            ORDER BY ub.earned_at DESC
            LIMIT 6
        """, (session['user_id'],))
        badges = cursor.fetchall()
        
        # Obter atividade recente
        cursor.execute("""
            SELECT *
            FROM activity_logs
            WHERE user_id = %s
            ORDER BY created_at DESC
            LIMIT 10
        """, (session['user_id'],))
        recent_activity = cursor.fetchall()
        
        return render_template('profile.html',
                             user_info=user_info,
                             next_level=next_level,
                             progress=progress,
                             category_stats=category_stats,
                             badges=badges,
                             recent_activity=recent_activity)
                             
    finally:
        cursor.close()
        conn.close()

def initialize_badges():
    """Inicializa as badges padrão se não existirem"""
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    try:
        # Verificar se já existem badges
        cursor.execute("SELECT COUNT(*) as count FROM badges")
        if cursor.fetchone()['count'] > 0:
            return
        
        # Badges gerais
        general_badges = [
            ('Iniciante', 'Atingiu 100 pontos totais', 'fas fa-star', None, 'total_points', 100),
            ('Dedicado', 'Completou 10 quizzes', 'fas fa-trophy', None, 'quizzes_completed', 10),
            ('Mestre', 'Atingiu 1000 pontos totais', 'fas fa-crown', None, 'total_points', 1000),
            ('Expert', 'Acertou 50 questões consecutivas', 'fas fa-award', None, 'consecutive_correct', 50)
        ]
        
        cursor.executemany("""
            INSERT INTO badges (name, description, icon, category_id, achievement_condition, achievement_threshold)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, general_badges)
        
        # Obter todas as categorias
        cursor.execute("SELECT category_id, name FROM categories")
        categories = cursor.fetchall()
        
        # Badges por categoria
        for category in categories:
            category_badges = [
                (f'Novato em {category["name"]}', f'Atingiu 100 pontos em {category["name"]}', 'fas fa-medal', 
                 category['category_id'], 'points_in_category', 100),
                (f'Especialista em {category["name"]}', f'Atingiu 500 pontos em {category["name"]}', 'fas fa-certificate', 
                 category['category_id'], 'points_in_category', 500),
                (f'Mestre em {category["name"]}', f'Atingiu 1000 pontos em {category["name"]}', 'fas fa-star', 
                 category['category_id'], 'points_in_category', 1000)
            ]
            
            cursor.executemany("""
                INSERT INTO badges (name, description, icon, category_id, achievement_condition, achievement_threshold)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, category_badges)
        
        conn.commit()
        print("Badges inicializadas com sucesso!")
        
    except Exception as e:
        conn.rollback()
        print(f"Erro ao inicializar badges: {str(e)}")
        
    finally:
        cursor.close()
        conn.close()

@app.route('/badges')
@login_required
def badges():
    # Inicializar badges se necessário
    initialize_badges()
    
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    try:
        # Obter informações do usuário e contagem de badges
        cursor.execute("""
            SELECT 
                u.*,
                COALESCE(COUNT(DISTINCT ub.badge_id), 0) as badges_count
            FROM users u
            LEFT JOIN user_badges ub ON u.user_id = ub.user_id
            WHERE u.user_id = %s
            GROUP BY u.user_id
        """, (session['user_id'],))
        user = cursor.fetchone()
        
        if not user:
            user = {'badges_count': 0}
        
        # Obter total de badges disponíveis
        cursor.execute("SELECT COUNT(*) as total FROM badges")
        total_badges = cursor.fetchone()['total']
        
        # Obter badges do usuário com data de conquista
        cursor.execute("""
            SELECT badge_id, earned_at
            FROM user_badges
            WHERE user_id = %s
        """, (session['user_id'],))
        user_badges = {row['badge_id']: row['earned_at'] for row in cursor.fetchall()}
        
        # Obter badges gerais (sem categoria)
        cursor.execute("""
            SELECT 
                b.*,
                CASE 
                    WHEN b.achievement_condition = 'total_points' 
                        THEN CONCAT('Alcance ', b.achievement_threshold, ' pontos totais')
                    WHEN b.achievement_condition = 'quizzes_completed' 
                        THEN CONCAT('Complete ', b.achievement_threshold, ' quizzes')
                    WHEN b.achievement_condition = 'consecutive_correct' 
                        THEN CONCAT('Acerte ', b.achievement_threshold, ' questões consecutivas')
                END as requirement
            FROM badges b
            WHERE b.category_id IS NULL
            ORDER BY b.achievement_threshold
        """)
        general_badges = cursor.fetchall()
        
        # Obter categorias
        cursor.execute("SELECT * FROM categories ORDER BY name")
        categories = cursor.fetchall()
        
        # Para cada categoria, obter suas badges
        for category in categories:
            cursor.execute("""
                SELECT 
                    b.*,
                    CONCAT('Alcance ', b.achievement_threshold, ' pontos em ', %s) as requirement
                FROM badges b
                WHERE b.category_id = %s
                ORDER BY b.achievement_threshold
            """, (category['name'], category['category_id']))
            category['badges'] = cursor.fetchall()
        
        # Obter progresso do usuário em cada categoria com valores padrão para campos nulos
        cursor.execute("""
            SELECT 
                c.category_id,
                COALESCE(uc.points, 0) as points,
                COALESCE(uc.correct_answers, 0) as correct_answers,
                COALESCE(uc.questions_answered, 0) as questions_answered,
                CASE 
                    WHEN uc.questions_answered > 0 
                    THEN ROUND((uc.correct_answers / uc.questions_answered) * 100, 2)
                    ELSE 0 
                END as accuracy
            FROM categories c
            LEFT JOIN user_categories uc ON c.category_id = uc.category_id AND uc.user_id = %s
        """, (session['user_id'],))
        category_progress = {row['category_id']: row for row in cursor.fetchall()}
        
        return render_template('badges.html',
                             user=user,
                             user_badges=user_badges,
                             total_badges=total_badges,
                             general_badges=general_badges,
                             categories=categories,
                             category_progress=category_progress)
                             
    finally:
        cursor.close()
        conn.close()

@app.route('/ranking')
def ranking():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    try:
        # Parâmetros
        page = request.args.get('page', 1, type=int)
        category_id = request.args.get('category', type=int)
        period = request.args.get('period', 'all')
        per_page = 20
        offset = (page - 1) * per_page
        
        # Construir query base
        if category_id:
            base_query = """
                SELECT 
                    u.user_id,
                    u.name,
                    l.level_name,
                    uc.points as total_points,
                    COUNT(DISTINCT ub.badge_id) as badges_count,
                    ROUND((uc.correct_answers / NULLIF(uc.questions_answered, 0)) * 100, 2) as accuracy
                FROM users u
                JOIN user_categories uc ON u.user_id = uc.user_id
                LEFT JOIN levels l ON u.current_level = l.level_id
                LEFT JOIN user_badges ub ON u.user_id = ub.user_id
                WHERE u.is_active = TRUE AND uc.category_id = %s
            """
            params = [category_id]
        else:
            base_query = """
                SELECT 
                    u.user_id,
                    u.name,
                    l.level_name,
                    u.total_points,
                    COUNT(DISTINCT ub.badge_id) as badges_count,
                    COALESCE(
                        (SELECT (SUM(ua.is_correct) / COUNT(*)) * 100
                         FROM user_answers ua
                         JOIN quiz_sessions qs ON ua.session_id = qs.session_id
                         WHERE qs.user_id = u.user_id),
                        0
                    ) as accuracy
                FROM users u
                LEFT JOIN levels l ON u.current_level = l.level_id
                LEFT JOIN user_badges ub ON u.user_id = ub.user_id
                WHERE u.is_active = TRUE
            """
            params = []
        
        # Adicionar filtro de período
        if period == 'week':
            base_query += " AND DATE(u.last_login) >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)"
        elif period == 'month':
            base_query += " AND DATE(u.last_login) >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)"
        
        # Agrupar e ordenar
        base_query += " GROUP BY u.user_id ORDER BY total_points DESC"
        
        # Contar total de registros
        count_query = f"SELECT COUNT(*) as total FROM ({base_query}) as subquery"
        cursor.execute(count_query, params)
        total = cursor.fetchone()['total']
        
        # Adicionar paginação
        base_query += " LIMIT %s OFFSET %s"
        params.extend([per_page, offset])
        
        # Executar query principal
        cursor.execute(base_query, params)
        ranking = cursor.fetchall()
        
        # Obter top 3 usuários
        cursor.execute(base_query.replace(" LIMIT %s OFFSET %s", " LIMIT 3"), params[:-2])
        top_users = cursor.fetchall()
        
        # Obter categorias para filtro
        cursor.execute("SELECT * FROM categories")
        categories = cursor.fetchall()
        
        # Obter nome da categoria selecionada
        category_name = None
        if category_id:
            cursor.execute("SELECT name FROM categories WHERE category_id = %s", (category_id,))
            result = cursor.fetchone()
            if result:
                category_name = result['name']
        
        # Calcular informações de paginação
        total_pages = (total + per_page - 1) // per_page
        pagination = {
            'page': page,
            'per_page': per_page,
            'total': total,
            'total_pages': total_pages,
            'start': offset + 1,
            'end': min(offset + per_page, total),
            'prev_page': page - 1 if page > 1 else None,
            'next_page': page + 1 if page < total_pages else None
        }
        
        return render_template('ranking.html',
                             ranking=ranking,
                             top_users=top_users,
                             categories=categories,
                             selected_category=category_id,
                             category_name=category_name,
                             period=period,
                             pagination=pagination,
                             current_user=session)
                             
    finally:
        cursor.close()
        conn.close()

# Rotas administrativas
@app.route('/admin')
@admin_required
def admin_dashboard():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Estatísticas gerais
    cursor.execute("""
        SELECT 
            COALESCE((SELECT COUNT(*) FROM users WHERE is_active = TRUE), 0) as active_users,
            COALESCE((SELECT COUNT(*) FROM questions WHERE is_active = TRUE), 0) as total_questions,
            COALESCE((SELECT COUNT(*) FROM quiz_sessions WHERE completed = TRUE), 0) as completed_quizzes,
            COALESCE(
                (SELECT (COALESCE(SUM(is_correct), 0) / NULLIF(COUNT(*), 0)) * 100 
                FROM user_answers), 
                0
            ) as accuracy
    """)
    stats = cursor.fetchone()
    
    # Estatísticas por categoria
    cursor.execute("""
        SELECT 
            c.name,
            COUNT(q.question_id) as question_count,
            ROUND(
                (COUNT(q.question_id) / NULLIF(
                    (SELECT COUNT(*) FROM questions WHERE is_active = TRUE), 0
                ) * 100), 
                1
            ) as percentage
        FROM categories c
        LEFT JOIN questions q ON c.category_id = q.category_id AND q.is_active = TRUE
        GROUP BY c.category_id, c.name
        ORDER BY question_count DESC
    """)
    category_stats = cursor.fetchall()
    
    # Garantir que percentage não seja None
    for cat in category_stats:
        if cat['percentage'] is None:
            cat['percentage'] = 0
    
    # Estatísticas por dificuldade
    cursor.execute("""
        SELECT 
            COALESCE(SUM(CASE WHEN d.difficulty_id = 1 THEN 1 ELSE 0 END), 0) as easy_count,
            COALESCE(SUM(CASE WHEN d.difficulty_id = 2 THEN 1 ELSE 0 END), 0) as medium_count,
            COALESCE(SUM(CASE WHEN d.difficulty_id = 3 THEN 1 ELSE 0 END), 0) as hard_count,
            COUNT(*) as total_count
        FROM questions q
        JOIN difficulties d ON q.difficulty_id = d.difficulty_id
        WHERE q.is_active = TRUE
    """)
    difficulty_counts = cursor.fetchone()
    
    total_questions = max(difficulty_counts['total_count'], 1)  # Garantir mínimo de 1 para evitar divisão por zero
    difficulty_stats = {
        'easy_count': difficulty_counts['easy_count'],
        'medium_count': difficulty_counts['medium_count'],
        'hard_count': difficulty_counts['hard_count'],
        'easy_percentage': (difficulty_counts['easy_count'] / total_questions) * 100,
        'medium_percentage': (difficulty_counts['medium_count'] / total_questions) * 100,
        'hard_percentage': (difficulty_counts['hard_count'] / total_questions) * 100
    }
    
    # Logs de atividade recente
    cursor.execute("""
        SELECT 
            l.*,
            COALESCE(u.name, 'Usuário Removido') as user_name
        FROM activity_logs l
        LEFT JOIN users u ON l.user_id = u.user_id
        ORDER BY l.created_at DESC
        LIMIT 10
    """)
    activity_logs = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('admin/dashboard.html',
                         stats=stats,
                         category_stats=category_stats,
                         difficulty_stats=difficulty_stats,
                         activity_logs=activity_logs)

@app.route('/admin/questions')
@admin_required
def admin_questions():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Parâmetros de paginação e filtros
    page = request.args.get('page', 1, type=int)
    per_page = 10
    offset = (page - 1) * per_page
    
    category = request.args.get('category')
    difficulty = request.args.get('difficulty')
    search = request.args.get('search')
    
    # Construir query base
    query = """
        SELECT 
            q.*,
            c.name as category_name,
            d.name as difficulty_name,
            t.name as type_name
        FROM questions q
        JOIN categories c ON q.category_id = c.category_id
        JOIN difficulties d ON q.difficulty_id = d.difficulty_id
        JOIN question_types t ON q.type_id = t.type_id
        WHERE 1=1
    """
    params = []
    
    # Adicionar filtros
    if category:
        query += " AND q.category_id = %s"
        params.append(category)
    if difficulty:
        query += " AND q.difficulty_id = %s"
        params.append(difficulty)
    if search:
        query += " AND q.content LIKE %s"
        params.append(f"%{search}%")
    
    # Contar total de registros
    count_query = f"SELECT COUNT(*) as total FROM ({query}) as subquery"
    cursor.execute(count_query, params)
    total = cursor.fetchone()['total']
    
    # Adicionar paginação
    query += " ORDER BY q.created_at DESC LIMIT %s OFFSET %s"
    params.extend([per_page, offset])
    
    # Executar query principal
    cursor.execute(query, params)
    questions = cursor.fetchall()
    
    # Obter categorias e dificuldades para filtros
    cursor.execute("SELECT * FROM categories")
    categories = cursor.fetchall()
    
    cursor.execute("SELECT * FROM difficulties")
    difficulties = cursor.fetchall()
    
    cursor.execute("SELECT * FROM question_types")
    question_types = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    # Calcular informações de paginação
    total_pages = (total + per_page - 1) // per_page
    pagination = {
        'page': page,
        'per_page': per_page,
        'total': total,
        'total_pages': total_pages,
        'start': offset + 1,
        'end': min(offset + per_page, total),
        'prev_page': page - 1 if page > 1 else None,
        'next_page': page + 1 if page < total_pages else None
    }
    
    return render_template('admin/questions.html',
                         questions=questions,
                         categories=categories,
                         difficulties=difficulties,
                         question_types=question_types,
                         pagination=pagination)

@app.route('/admin/questions', methods=['POST'])
@admin_required
def admin_add_question():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    try:
        # Inserir pergunta
        cursor.execute("""
            INSERT INTO questions 
            (content, category_id, difficulty_id, type_id, base_points, created_by)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (
            request.form['content'],
            request.form['category_id'],
            request.form['difficulty_id'],
            request.form['type_id'],
            calculate_base_points(request.form['difficulty_id']),
            session['user_id']
        ))
        
        question_id = cursor.lastrowid
        
        # Inserir alternativas ou resposta escrita
        if request.form['type_id'] == '1':  # Múltipla escolha
            alternatives = request.form.getlist('alternatives[]')
            correct_index = int(request.form['correct_alternative'])
            
            for i, alternative in enumerate(alternatives):
                cursor.execute("""
                    INSERT INTO alternatives 
                    (question_id, content, is_correct)
                    VALUES (%s, %s, %s)
                """, (question_id, alternative, i == correct_index))
        else:  # Resposta escrita
            cursor.execute("""
                INSERT INTO written_answers 
                (question_id, correct_answer, alternative_answers)
                VALUES (%s, %s, %s)
            """, (
                question_id,
                request.form['correct_answer'],
                request.form.get('alternative_answers', '')
            ))
        
        # Inserir feedback
        cursor.execute("""
            INSERT INTO question_feedback
            (question_id, correct_feedback, incorrect_feedback)
            VALUES (%s, %s, %s)
        """, (
            question_id,
            request.form.get('correct_feedback', 'Parabéns! Você acertou!'),
            request.form.get('incorrect_feedback', 'Ops! Tente novamente.')
        ))
        
        conn.commit()
        flash('Pergunta adicionada com sucesso!', 'success')
        
    except Exception as e:
        conn.rollback()
        flash(f'Erro ao adicionar pergunta: {str(e)}', 'danger')
    
    finally:
        cursor.close()
        conn.close()
    
    return redirect(url_for('admin_questions'))

@app.route('/admin/questions/<int:question_id>', methods=['GET'])
@admin_required
def admin_get_question(question_id):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obter dados da pergunta
    cursor.execute("""
        SELECT q.*, qf.correct_feedback, qf.incorrect_feedback
        FROM questions q
        LEFT JOIN question_feedback qf ON q.question_id = qf.question_id
        WHERE q.question_id = %s
    """, (question_id,))
    question = cursor.fetchone()
    
    if not question:
        cursor.close()
        conn.close()
        return jsonify({'error': 'Pergunta não encontrada'}), 404
    
    # Obter alternativas ou resposta escrita
    if question['type_id'] == 1:  # Múltipla escolha
        cursor.execute("""
            SELECT * FROM alternatives 
            WHERE question_id = %s
            ORDER BY alternative_id
        """, (question_id,))
        question['alternatives'] = cursor.fetchall()
    else:  # Resposta escrita
        cursor.execute("""
            SELECT * FROM written_answers 
            WHERE question_id = %s
        """, (question_id,))
        answer = cursor.fetchone()
        if answer:
            question['correct_answer'] = answer['correct_answer']
            question['alternative_answers'] = answer['alternative_answers']
    
    cursor.close()
    conn.close()
    
    return jsonify(question)

@app.route('/admin/questions/<int:question_id>', methods=['PUT'])
@admin_required
def admin_update_question(question_id):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    try:
        data = request.get_json()
        
        # Atualizar pergunta
        cursor.execute("""
            UPDATE questions 
            SET content = %s,
                category_id = %s,
                difficulty_id = %s,
                type_id = %s,
                base_points = %s
            WHERE question_id = %s
        """, (
            data['content'],
            data['category_id'],
            data['difficulty_id'],
            data['type_id'],
            calculate_base_points(data['difficulty_id']),
            question_id
        ))
        
        # Atualizar alternativas ou resposta escrita
        if data['type_id'] == 1:  # Múltipla escolha
            # Remover alternativas antigas
            cursor.execute("DELETE FROM alternatives WHERE question_id = %s", (question_id,))
            
            # Inserir novas alternativas
            for i, alternative in enumerate(data['alternatives']):
                cursor.execute("""
                    INSERT INTO alternatives 
                    (question_id, content, is_correct)
                    VALUES (%s, %s, %s)
                """, (question_id, alternative['content'], alternative['is_correct']))
        else:  # Resposta escrita
            cursor.execute("""
                INSERT INTO written_answers 
                (question_id, correct_answer, alternative_answers)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    correct_answer = VALUES(correct_answer),
                    alternative_answers = VALUES(alternative_answers)
            """, (
                question_id,
                data['correct_answer'],
                data.get('alternative_answers', '')
            ))
        
        # Atualizar feedback
        cursor.execute("""
            INSERT INTO question_feedback
            (question_id, correct_feedback, incorrect_feedback)
            VALUES (%s, %s, %s)
            ON DUPLICATE KEY UPDATE
                correct_feedback = VALUES(correct_feedback),
                incorrect_feedback = VALUES(incorrect_feedback)
        """, (
            question_id,
            data.get('correct_feedback', 'Parabéns! Você acertou!'),
            data.get('incorrect_feedback', 'Ops! Tente novamente.')
        ))
        
        conn.commit()
        return jsonify({'success': True})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    
    finally:
        cursor.close()
        conn.close()

@app.route('/admin/questions/<int:question_id>', methods=['DELETE'])
@admin_required
def admin_delete_question(question_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        # Verificar se a pergunta existe
        cursor.execute("SELECT 1 FROM questions WHERE question_id = %s", (question_id,))
        if not cursor.fetchone():
            return jsonify({'error': 'Pergunta não encontrada'}), 404
        
        # Excluir pergunta (as alternativas e respostas serão excluídas automaticamente devido à constraint ON DELETE CASCADE)
        cursor.execute("DELETE FROM questions WHERE question_id = %s", (question_id,))
        conn.commit()
        
        return jsonify({'success': True})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    
    finally:
        cursor.close()
        conn.close()

@app.route('/admin/questions/<int:question_id>/toggle', methods=['POST'])
@admin_required
def admin_toggle_question(question_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        # Alternar status da pergunta
        cursor.execute("""
            UPDATE questions 
            SET is_active = NOT is_active
            WHERE question_id = %s
        """, (question_id,))
        conn.commit()
        
        return jsonify({'success': True})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    
    finally:
        cursor.close()
        conn.close()

@app.route('/admin/import_questions', methods=['POST'])
@admin_required
def admin_import_questions():
    if 'csv_file' not in request.files:
        flash('Nenhum arquivo selecionado', 'danger')
        return redirect(url_for('admin_questions'))
    
    file = request.files['csv_file']
    if file.filename == '':
        flash('Nenhum arquivo selecionado', 'danger')
        return redirect(url_for('admin_questions'))
    
    if not file.filename.endswith('.csv'):
        flash('Arquivo deve ser do tipo CSV', 'danger')
        return redirect(url_for('admin_questions'))
    
    try:
        # Processar arquivo CSV
        stream = io.StringIO(file.stream.read().decode("UTF8"), newline=None)
        csv_reader = csv.DictReader(stream)
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        for row in csv_reader:
            # Inserir pergunta
            cursor.execute("""
                INSERT INTO questions 
                (content, category_id, difficulty_id, type_id, base_points, created_by)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                row['content'],
                row['category_id'],
                row['difficulty_id'],
                row['type_id'],
                calculate_base_points(row['difficulty_id']),
                session['user_id']
            ))
            
            question_id = cursor.lastrowid
            
            # Inserir alternativas ou resposta escrita
            if row['type_id'] == '1':  # Múltipla escolha
                alternatives = row['alternatives'].split('|')
                correct_index = int(row['correct_alternative'])
                
                for i, alternative in enumerate(alternatives):
                    cursor.execute("""
                        INSERT INTO alternatives 
                        (question_id, content, is_correct)
                        VALUES (%s, %s, %s)
                    """, (question_id, alternative.strip(), i == correct_index))
            else:  # Resposta escrita
                cursor.execute("""
                    INSERT INTO written_answers 
                    (question_id, correct_answer, alternative_answers)
                    VALUES (%s, %s, %s)
                """, (
                    question_id,
                    row['correct_answer'],
                    row.get('alternative_answers', '')
                ))
        
        conn.commit()
        flash('Perguntas importadas com sucesso!', 'success')
        
    except Exception as e:
        conn.rollback()
        flash(f'Erro ao importar perguntas: {str(e)}', 'danger')
    
    finally:
        cursor.close()
        conn.close()
    
    return redirect(url_for('admin_questions'))

def calculate_base_points(difficulty_id):
    """Calcula os pontos base para uma pergunta com base na dificuldade"""
    points_map = {
        '1': 10,  # Fácil
        '2': 20,  # Médio
        '3': 30   # Difícil
    }
    return points_map.get(str(difficulty_id), 10)

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

@app.route('/admin/categories')
@admin_required
def admin_categories():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obter categorias com estatísticas
    cursor.execute("""
        SELECT 
            c.*,
            COUNT(DISTINCT q.question_id) as question_count,
            COUNT(DISTINCT CASE WHEN q.difficulty_id = 1 THEN q.question_id END) as easy_count,
            COUNT(DISTINCT CASE WHEN q.difficulty_id = 2 THEN q.question_id END) as medium_count,
            COUNT(DISTINCT CASE WHEN q.difficulty_id = 3 THEN q.question_id END) as hard_count,
            COUNT(DISTINCT uc.user_id) as active_users,
            COALESCE(AVG(CASE WHEN ua.is_correct = 1 THEN 100 ELSE 0 END), 0) as accuracy
        FROM categories c
        LEFT JOIN questions q ON c.category_id = q.category_id
        LEFT JOIN user_categories uc ON c.category_id = uc.category_id
        LEFT JOIN quiz_sessions qs ON c.category_id = qs.category_id
        LEFT JOIN user_answers ua ON qs.session_id = ua.session_id
        GROUP BY c.category_id
        ORDER BY c.name
    """)
    categories = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return render_template('admin/categories.html', categories=categories)

@app.route('/admin/categories', methods=['POST'])
@admin_required
def admin_add_category():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        cursor.execute("""
            INSERT INTO categories (name, description, icon)
            VALUES (%s, %s, %s)
        """, (
            request.form['name'],
            request.form.get('description', ''),
            request.form.get('icon', '')
        ))
        
        conn.commit()
        flash('Categoria adicionada com sucesso!', 'success')
        
    except Exception as e:
        conn.rollback()
        flash(f'Erro ao adicionar categoria: {str(e)}', 'danger')
    
    finally:
        cursor.close()
        conn.close()
    
    return redirect(url_for('admin_categories'))

@app.route('/admin/categories/<int:category_id>', methods=['GET'])
@admin_required
def admin_get_category(category_id):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    cursor.execute("""
        SELECT * FROM categories WHERE category_id = %s
    """, (category_id,))
    category = cursor.fetchone()
    
    cursor.close()
    conn.close()
    
    if not category:
        return jsonify({'error': 'Categoria não encontrada'}), 404
    
    return jsonify(category)

@app.route('/admin/categories/<int:category_id>', methods=['PUT'])
@admin_required
def admin_update_category(category_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        data = request.get_json()
        
        cursor.execute("""
            UPDATE categories 
            SET name = %s,
                description = %s,
                icon = %s
            WHERE category_id = %s
        """, (
            data['name'],
            data.get('description', ''),
            data.get('icon', ''),
            category_id
        ))
        
        conn.commit()
        return jsonify({'success': True})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    
    finally:
        cursor.close()
        conn.close()

@app.route('/admin/categories/<int:category_id>', methods=['DELETE'])
@admin_required
def admin_delete_category(category_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        # Verificar se existem perguntas na categoria
        cursor.execute("""
            SELECT COUNT(*) as count 
            FROM questions 
            WHERE category_id = %s
        """, (category_id,))
        
        if cursor.fetchone()['count'] > 0:
            return jsonify({
                'error': 'Não é possível excluir uma categoria que possui perguntas'
            }), 400
        
        cursor.execute("DELETE FROM categories WHERE category_id = %s", (category_id,))
        conn.commit()
        
        return jsonify({'success': True})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    
    finally:
        cursor.close()
        conn.close()

@app.route('/admin/users')
@admin_required
def admin_users():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Parâmetros de paginação e filtros
    page = request.args.get('page', 1, type=int)
    per_page = 10
    offset = (page - 1) * per_page
    
    search = request.args.get('search')
    
    # Construir query base
    query = """
        SELECT 
            u.*,
            l.level_name,
            COUNT(DISTINCT qs.session_id) as quizzes_completed,
            COALESCE(AVG(CASE WHEN ua.is_correct = 1 THEN 100 ELSE 0 END), 0) as accuracy,
            COUNT(DISTINCT ub.badge_id) as badges_count
        FROM users u
        LEFT JOIN levels l ON u.current_level = l.level_id
        LEFT JOIN quiz_sessions qs ON u.user_id = qs.user_id AND qs.completed = TRUE
        LEFT JOIN user_answers ua ON qs.session_id = ua.session_id
        LEFT JOIN user_badges ub ON u.user_id = ub.user_id
        WHERE u.user_id != %s
    """
    params = [session['user_id']]  # Excluir o usuário atual da lista
    
    # Adicionar filtro de busca
    if search:
        query += " AND (u.name LIKE %s OR u.email LIKE %s)"
        search_param = f"%{search}%"
        params.extend([search_param, search_param])
    
    # Agrupar e ordenar
    query += " GROUP BY u.user_id ORDER BY u.name"
    
    # Contar total de registros
    count_query = f"SELECT COUNT(*) as total FROM ({query}) as subquery"
    cursor.execute(count_query, params)
    total = cursor.fetchone()['total']
    
    # Adicionar paginação
    query += " LIMIT %s OFFSET %s"
    params.extend([per_page, offset])
    
    # Executar query principal
    cursor.execute(query, params)
    users = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    # Calcular informações de paginação
    total_pages = (total + per_page - 1) // per_page
    pagination = {
        'page': page,
        'per_page': per_page,
        'total': total,
        'total_pages': total_pages,
        'start': offset + 1,
        'end': min(offset + per_page, total),
        'prev_page': page - 1 if page > 1 else None,
        'next_page': page + 1 if page < total_pages else None
    }
    
    return render_template('admin/users.html',
                         users=users,
                         pagination=pagination)

@app.route('/admin/users/<int:user_id>', methods=['GET'])
@admin_required
def admin_get_user(user_id):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    
    # Obter informações detalhadas do usuário
    cursor.execute("""
        SELECT 
            u.*,
            l.level_name,
            COUNT(DISTINCT qs.session_id) as quizzes_completed,
            COALESCE(AVG(CASE WHEN ua.is_correct = 1 THEN 100 ELSE 0 END), 0) as accuracy,
            COUNT(DISTINCT ub.badge_id) as badges_count
        FROM users u
        LEFT JOIN levels l ON u.current_level = l.level_id
        LEFT JOIN quiz_sessions qs ON u.user_id = qs.user_id AND qs.completed = TRUE
        LEFT JOIN user_answers ua ON qs.session_id = ua.session_id
        LEFT JOIN user_badges ub ON u.user_id = ub.user_id
        WHERE u.user_id = %s
        GROUP BY u.user_id
    """, (user_id,))
    user = cursor.fetchone()
    
    if not user:
        cursor.close()
        conn.close()
        return jsonify({'error': 'Usuário não encontrado'}), 404
    
    # Obter estatísticas por categoria
    cursor.execute("""
        SELECT 
            c.name,
            uc.points,
            uc.questions_answered,
            uc.correct_answers,
            ROUND((uc.correct_answers / NULLIF(uc.questions_answered, 0)) * 100, 2) as accuracy
        FROM user_categories uc
        JOIN categories c ON uc.category_id = c.category_id
        WHERE uc.user_id = %s
        ORDER BY uc.points DESC
    """, (user_id,))
    category_stats = cursor.fetchall()
    
    # Obter badges do usuário
    cursor.execute("""
        SELECT b.*, ub.earned_at
        FROM badges b
        JOIN user_badges ub ON b.badge_id = ub.badge_id
        WHERE ub.user_id = %s
        ORDER BY ub.earned_at DESC
    """, (user_id,))
    badges = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return jsonify({
        'user': user,
        'category_stats': category_stats,
        'badges': badges
    })

@app.route('/admin/users/<int:user_id>/toggle', methods=['POST'])
@admin_required
def admin_toggle_user(user_id):
    if user_id == session['user_id']:
        return jsonify({'error': 'Não é possível desativar seu próprio usuário'}), 400
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        cursor.execute("""
            UPDATE users 
            SET is_active = NOT is_active
            WHERE user_id = %s
        """, (user_id,))
        conn.commit()
        
        return jsonify({'success': True})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    
    finally:
        cursor.close()
        conn.close()

@app.route('/admin/users/<int:user_id>/reset-password', methods=['POST'])
@admin_required
def admin_reset_user_password(user_id):
    if user_id == session['user_id']:
        return jsonify({'error': 'Use a página de perfil para alterar sua própria senha'}), 400
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        # Gerar nova senha aleatória
        new_password = ''.join(random.choices('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', k=12))
        hashed_password = bcrypt.hashpw(new_password.encode('utf-8'), bcrypt.gensalt())
        
        cursor.execute("""
            UPDATE users 
            SET password_hash = %s
            WHERE user_id = %s
        """, (hashed_password, user_id))
        
        # Obter e-mail do usuário
        cursor.execute("SELECT email FROM users WHERE user_id = %s", (user_id,))
        user_email = cursor.fetchone()['email']
        
        conn.commit()
        
        # Enviar e-mail com a nova senha
        msg = Message(
            'Sua senha foi redefinida - Quiz TI',
            sender=app.config['MAIL_DEFAULT_SENDER'],
            recipients=[user_email]
        )
        msg.body = f"""
        Sua senha foi redefinida pelo administrador.
        
        Nova senha: {new_password}
        
        Por favor, altere esta senha após o próximo login.
        """
        mail.send(msg)
        
        return jsonify({'success': True})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    
    finally:
        cursor.close()
        conn.close()

if __name__ == '__main__':
    app.run(debug=True) 
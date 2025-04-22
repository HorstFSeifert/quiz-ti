-- Script SQL para criação do banco de dados da aplicação de Quiz em TI
-- Compatível com MySQL/XAMPP
-- Inclui tabelas, triggers, índices e funções para automatização

-- Criação do banco de dados
DROP DATABASE IF EXISTS quiz_ti;
CREATE DATABASE quiz_ti CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE quiz_ti;

-- Tabela de Usuários
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    reset_token VARCHAR(255) NULL,
    reset_token_expires TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE,
    total_points INT DEFAULT 0,
    current_level INT DEFAULT 1,
    consecutive_correct_answers INT DEFAULT 0,
    INDEX idx_email (email),
    INDEX idx_points (total_points)
) ENGINE=InnoDB;

-- Tabela de Níveis
CREATE TABLE levels (
    level_id INT AUTO_INCREMENT PRIMARY KEY,
    level_name VARCHAR(50) NOT NULL,
    min_points INT NOT NULL,
    max_points INT NOT NULL,
    description VARCHAR(255),
    UNIQUE KEY unique_level_range (min_points, max_points)
) ENGINE=InnoDB;

-- Tabela de Categorias
CREATE TABLE categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(255),
    icon VARCHAR(100)
) ENGINE=InnoDB;

-- Tabela de Dificuldades
CREATE TABLE difficulties (
    difficulty_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    points_multiplier DECIMAL(3,1) NOT NULL,
    time_limit INT, -- Segundos por pergunta
    description VARCHAR(255)
) ENGINE=InnoDB;

-- Tabela de Tipos de Perguntas
CREATE TABLE question_types (
    type_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(255)
) ENGINE=InnoDB;

-- Tabela de Perguntas
CREATE TABLE questions (
    question_id INT AUTO_INCREMENT PRIMARY KEY,
    content TEXT NOT NULL,
    category_id INT NOT NULL,
    difficulty_id INT NOT NULL,
    type_id INT NOT NULL,
    base_points INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (category_id) REFERENCES categories(category_id),
    FOREIGN KEY (difficulty_id) REFERENCES difficulties(difficulty_id),
    FOREIGN KEY (type_id) REFERENCES question_types(type_id),
    FOREIGN KEY (created_by) REFERENCES users(user_id),
    INDEX idx_category_difficulty (category_id, difficulty_id)
) ENGINE=InnoDB;

-- Tabela de Alternativas (para perguntas de múltipla escolha)
CREATE TABLE alternatives (
    alternative_id INT AUTO_INCREMENT PRIMARY KEY,
    question_id INT NOT NULL,
    content TEXT NOT NULL,
    is_correct BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (question_id) REFERENCES questions(question_id) ON DELETE CASCADE,
    INDEX idx_question (question_id)
) ENGINE=InnoDB;

-- Tabela de Respostas Escritas (gabarito para perguntas de resposta escrita)
CREATE TABLE written_answers (
    answer_id INT AUTO_INCREMENT PRIMARY KEY,
    question_id INT NOT NULL UNIQUE,
    correct_answer TEXT NOT NULL,
    alternative_answers TEXT, -- Armazena alternativas válidas separadas por pipe (|)
    FOREIGN KEY (question_id) REFERENCES questions(question_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Tabela de Sessões de Quiz
CREATE TABLE quiz_sessions (
    session_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    category_id INT NOT NULL,
    difficulty_id INT NOT NULL,
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP NULL,
    total_points INT DEFAULT 0,
    accuracy_percentage DECIMAL(5,2) DEFAULT 0,
    completed BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (category_id) REFERENCES categories(category_id),
    FOREIGN KEY (difficulty_id) REFERENCES difficulties(difficulty_id),
    INDEX idx_user_completed (user_id, completed)
) ENGINE=InnoDB;

-- Tabela de Respostas do Usuário
CREATE TABLE user_answers (
    answer_id INT AUTO_INCREMENT PRIMARY KEY,
    session_id INT NOT NULL,
    question_id INT NOT NULL,
    alternative_id INT NULL, -- Para múltipla escolha
    written_response TEXT NULL, -- Para resposta escrita
    is_correct BOOLEAN DEFAULT FALSE,
    points_earned INT DEFAULT 0,
    response_time INT NULL, -- Tempo em segundos
    answered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES quiz_sessions(session_id),
    FOREIGN KEY (question_id) REFERENCES questions(question_id),
    FOREIGN KEY (alternative_id) REFERENCES alternatives(alternative_id),
    INDEX idx_session (session_id),
    INDEX idx_question (question_id)
) ENGINE=InnoDB;

-- Tabela de Conquistas/Badges
CREATE TABLE badges (
    badge_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description VARCHAR(255) NOT NULL,
    icon VARCHAR(100),
    category_id INT NULL, -- NULL significa que é uma badge geral
    achievement_condition VARCHAR(255) NOT NULL, -- Descrição da condição para ganhar
    achievement_threshold INT NOT NULL, -- Valor numérico necessário para desbloquear
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
) ENGINE=InnoDB;

-- Tabela de Badges do Usuário (relação muitos-para-muitos)
CREATE TABLE user_badges (
    user_id INT NOT NULL,
    badge_id INT NOT NULL,
    earned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, badge_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (badge_id) REFERENCES badges(badge_id)
) ENGINE=InnoDB;

-- Tabela de Categoria de Usuários (para pontuação por categoria)
CREATE TABLE user_categories (
    user_id INT NOT NULL,
    category_id INT NOT NULL,
    points INT DEFAULT 0,
    questions_answered INT DEFAULT 0,
    correct_answers INT DEFAULT 0,
    PRIMARY KEY (user_id, category_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (category_id) REFERENCES categories(category_id),
    INDEX idx_category_points (category_id, points)
) ENGINE=InnoDB;

-- Tabela de configurações do sistema
CREATE TABLE system_settings (
    setting_id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(100) NOT NULL UNIQUE,
    setting_value TEXT NOT NULL,
    description VARCHAR(255),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabela de logs de atividades
CREATE TABLE activity_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action_type VARCHAR(50) NOT NULL,
    action_description TEXT NOT NULL,
    ip_address VARCHAR(45),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    INDEX idx_user_action (user_id, action_type),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB;

-- ==========================================
-- TRIGGERS
-- ==========================================

-- Trigger para atualizar nível do usuário automaticamente
DELIMITER //
CREATE TRIGGER update_user_level BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    DECLARE new_level INT;
    
    SELECT level_id INTO new_level FROM levels 
    WHERE NEW.total_points BETWEEN min_points AND max_points 
    LIMIT 1;
    
    IF new_level IS NOT NULL THEN
        SET NEW.current_level = new_level;
    END IF;
END//
DELIMITER ;

-- Trigger para registrar quando uma sessão de quiz é completada
DELIMITER //
CREATE TRIGGER complete_quiz_session BEFORE UPDATE ON quiz_sessions
FOR EACH ROW
BEGIN
    IF NEW.completed = TRUE AND OLD.completed = FALSE THEN
        SET NEW.end_time = CURRENT_TIMESTAMP;
        
        -- Calcular precisão
        SET NEW.accuracy_percentage = (
            SELECT (SUM(is_correct) / COUNT(*)) * 100 
            FROM user_answers 
            WHERE session_id = NEW.session_id
        );
    END IF;
END//
DELIMITER ;

-- Trigger para atualizar pontos do usuário quando uma resposta é registrada
DELIMITER //
CREATE TRIGGER update_user_points_after_answer AFTER INSERT ON user_answers
FOR EACH ROW
BEGIN
    DECLARE session_user_id INT;
    DECLARE question_category_id INT;
    
    -- Obter o ID do usuário pela sessão
    SELECT user_id INTO session_user_id 
    FROM quiz_sessions 
    WHERE session_id = NEW.session_id;
    
    -- Obter a categoria da pergunta
    SELECT category_id INTO question_category_id 
    FROM questions 
    WHERE question_id = NEW.question_id;
    
    -- Atualizar pontos totais do usuário
    UPDATE users 
    SET total_points = total_points + NEW.points_earned,
        consecutive_correct_answers = IF(NEW.is_correct, consecutive_correct_answers + 1, 0)
    WHERE user_id = session_user_id;
    
    -- Atualizar pontos da sessão
    UPDATE quiz_sessions 
    SET total_points = total_points + NEW.points_earned 
    WHERE session_id = NEW.session_id;
    
    -- Atualizar pontos do usuário por categoria
    INSERT INTO user_categories (user_id, category_id, points, questions_answered, correct_answers)
    VALUES (session_user_id, question_category_id, NEW.points_earned, 1, IF(NEW.is_correct, 1, 0))
    ON DUPLICATE KEY UPDATE
        points = points + NEW.points_earned,
        questions_answered = questions_answered + 1,
        correct_answers = correct_answers + IF(NEW.is_correct, 1, 0);
    
    -- Verificar badges baseadas em pontos por categoria
    INSERT INTO user_badges (user_id, badge_id)
    SELECT session_user_id, b.badge_id
    FROM badges b
    JOIN user_categories uc ON uc.category_id = b.category_id
    WHERE uc.user_id = session_user_id
      AND uc.category_id = question_category_id
      AND b.achievement_condition = 'points_in_category'
      AND uc.points >= b.achievement_threshold
      AND NOT EXISTS (
          SELECT 1 FROM user_badges ub 
          WHERE ub.user_id = session_user_id AND ub.badge_id = b.badge_id
      );
      
    -- Verificar badges baseadas em respostas corretas
    IF NEW.is_correct THEN
        INSERT INTO user_badges (user_id, badge_id)
        SELECT session_user_id, b.badge_id
        FROM badges b
        JOIN user_categories uc ON uc.category_id = b.category_id OR b.category_id IS NULL
        WHERE uc.user_id = session_user_id
          AND (uc.category_id = question_category_id OR b.category_id IS NULL)
          AND b.achievement_condition = 'correct_answers'
          AND uc.correct_answers >= b.achievement_threshold
          AND NOT EXISTS (
              SELECT 1 FROM user_badges ub 
              WHERE ub.user_id = session_user_id AND ub.badge_id = b.badge_id
          );
    END IF;
    
    -- Verificar badges baseadas em sequência de acertos
    INSERT INTO user_badges (user_id, badge_id)
    SELECT session_user_id, b.badge_id
    FROM badges b, users u
    WHERE u.user_id = session_user_id
      AND b.achievement_condition = 'consecutive_correct'
      AND u.consecutive_correct_answers >= b.achievement_threshold
      AND NOT EXISTS (
          SELECT 1 FROM user_badges ub 
          WHERE ub.user_id = session_user_id AND ub.badge_id = b.badge_id
      );
END//
DELIMITER ;

-- Trigger para calcular pontos com base no tempo de resposta
DELIMITER //
CREATE TRIGGER calculate_points_on_answer BEFORE INSERT ON user_answers
FOR EACH ROW
BEGIN
    DECLARE base_pts INT;
    DECLARE difficulty_mult DECIMAL(3,1);
    DECLARE time_limit INT;
    DECLARE time_bonus INT;
    DECLARE session_difficulty_id INT;
    DECLARE consecutive_bonus INT;
    DECLARE user_consecutive INT;
    DECLARE session_user_id INT;
    
    -- Obter pontos base da pergunta
    SELECT base_points INTO base_pts 
    FROM questions 
    WHERE question_id = NEW.question_id;
    
    -- Obter informações da sessão
    SELECT s.difficulty_id, s.user_id INTO session_difficulty_id, session_user_id
    FROM quiz_sessions s
    WHERE s.session_id = NEW.session_id;
    
    -- Obter multiplicador de dificuldade e tempo limite
    SELECT points_multiplier, time_limit INTO difficulty_mult, time_limit
    FROM difficulties 
    WHERE difficulty_id = session_difficulty_id;
    
    -- Obter acertos consecutivos do usuário
    SELECT consecutive_correct_answers INTO user_consecutive
    FROM users
    WHERE user_id = session_user_id;
    
    -- Calcular bônus de acertos consecutivos (10% a cada 3 acertos consecutivos)
    SET consecutive_bonus = FLOOR(user_consecutive / 3) * 10;
    
    -- Calcular bônus de tempo (se respondeu antes de 50% do tempo)
    IF NEW.is_correct AND NEW.response_time IS NOT NULL AND time_limit IS NOT NULL THEN
        IF NEW.response_time <= (time_limit / 2) THEN
            SET time_bonus = 20; -- 20% de bônus por resposta rápida
        ELSE
            SET time_bonus = 0;
        END IF;
    ELSE
        SET time_bonus = 0;
    END IF;
    
    -- Calcular pontos finais (apenas se a resposta estiver correta)
    IF NEW.is_correct THEN
        SET NEW.points_earned = ROUND(
            base_pts * difficulty_mult * (1 + (time_bonus / 100)) * (1 + (consecutive_bonus / 100))
        );
    ELSE
        SET NEW.points_earned = 0;
    END IF;
END//
DELIMITER ;

-- Trigger para verificar se a resposta está correta (múltipla escolha)
DELIMITER //
CREATE TRIGGER check_multiple_choice_correctness BEFORE INSERT ON user_answers
FOR EACH ROW
BEGIN
    DECLARE question_type INT;
    DECLARE is_correct_answer BOOLEAN DEFAULT FALSE;
    
    -- Obter o tipo da pergunta
    SELECT type_id INTO question_type 
    FROM questions 
    WHERE question_id = NEW.question_id;
    
    -- Para múltipla escolha
    IF question_type = 1 AND NEW.alternative_id IS NOT NULL THEN
        SELECT is_correct INTO is_correct_answer
        FROM alternatives
        WHERE alternative_id = NEW.alternative_id AND question_id = NEW.question_id;
        
        SET NEW.is_correct = is_correct_answer;
    
    -- Para resposta escrita
    ELSEIF question_type = 2 AND NEW.written_response IS NOT NULL THEN
        DECLARE correct_ans TEXT;
        DECLARE alt_answers TEXT;
        
        -- Obter resposta correta
        SELECT correct_answer, alternative_answers 
        INTO correct_ans, alt_answers
        FROM written_answers 
        WHERE question_id = NEW.question_id;
        
        -- Verificar se a resposta está correta (case-insensitive)
        IF LOWER(NEW.written_response) = LOWER(correct_ans) THEN
            SET NEW.is_correct = TRUE;
        ELSEIF alt_answers IS NOT NULL THEN
            -- Verificar respostas alternativas (separadas por |)
            SET @found = 0;
            
            -- Iterar sobre respostas alternativas
            SET @pos = 1;
            SET @len = CHAR_LENGTH(alt_answers);
            
            WHILE @pos <= @len AND @found = 0 DO
                SET @next_pos = LOCATE('|', alt_answers, @pos);
                IF @next_pos = 0 THEN
                    SET @next_pos = @len + 1;
                END IF;
                
                SET @alt = SUBSTRING(alt_answers, @pos, @next_pos - @pos);
                IF LOWER(NEW.written_response) = LOWER(TRIM(@alt)) THEN
                    SET @found = 1;
                END IF;
                
                SET @pos = @next_pos + 1;
            END WHILE;
            
            SET NEW.is_correct = IF(@found = 1, TRUE, FALSE);
        ELSE
            SET NEW.is_correct = FALSE;
        END IF;
    END IF;
END//
DELIMITER ;

-- Trigger para registrar atividades do usuário
DELIMITER //
CREATE TRIGGER log_user_registration AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO activity_logs (user_id, action_type, action_description)
    VALUES (NEW.user_id, 'USER_REGISTER', CONCAT('Novo usuário registrado: ', NEW.name));
END//
DELIMITER ;

-- ==========================================
-- STORED PROCEDURES
-- ==========================================

-- Procedimento para iniciar uma nova sessão de quiz
DELIMITER //
CREATE PROCEDURE start_quiz_session(
    IN p_user_id INT,
    IN p_category_id INT,
    IN p_difficulty_id INT,
    OUT p_session_id INT
)
BEGIN
    INSERT INTO quiz_sessions (user_id, category_id, difficulty_id)
    VALUES (p_user_id, p_category_id, p_difficulty_id);
    
    SET p_session_id = LAST_INSERT_ID();
    
    -- Registrar no log
    INSERT INTO activity_logs (user_id, action_type, action_description)
    VALUES (p_user_id, 'START_QUIZ', CONCAT('Iniciou quiz na categoria ', p_category_id, ' com dificuldade ', p_difficulty_id));
END//
DELIMITER ;

-- Procedimento para obter perguntas para um quiz
DELIMITER //
CREATE PROCEDURE get_quiz_questions(
    IN p_category_id INT,
    IN p_difficulty_id INT,
    IN p_limit INT
)
BEGIN
    -- Selecionando perguntas aleatórias da categoria e dificuldade especificadas
    SELECT q.question_id, q.content, q.type_id, q.base_points
    FROM questions q
    WHERE q.category_id = p_category_id
      AND q.difficulty_id = p_difficulty_id
      AND q.is_active = TRUE
    ORDER BY RAND()
    LIMIT p_limit;
END//
DELIMITER ;

-- Procedimento para obter alternativas de uma pergunta
DELIMITER //
CREATE PROCEDURE get_question_alternatives(
    IN p_question_id INT
)
BEGIN
    SELECT alternative_id, content
    FROM alternatives
    WHERE question_id = p_question_id
    ORDER BY RAND(); -- Aleatorizar a ordem das alternativas
END//
DELIMITER ;

-- Procedimento para salvar resposta do usuário
DELIMITER //
CREATE PROCEDURE save_user_answer(
    IN p_session_id INT,
    IN p_question_id INT,
    IN p_alternative_id INT,
    IN p_written_response TEXT,
    IN p_response_time INT
)
BEGIN
    -- A verificação da resposta e cálculo de pontos é feito por triggers
    INSERT INTO user_answers (session_id, question_id, alternative_id, written_response, response_time)
    VALUES (p_session_id, p_question_id, p_alternative_id, p_written_response, p_response_time);
END//
DELIMITER ;

-- Procedimento para finalizar uma sessão de quiz
DELIMITER //
CREATE PROCEDURE complete_quiz_session(
    IN p_session_id INT
)
BEGIN
    UPDATE quiz_sessions
    SET completed = TRUE
    WHERE session_id = p_session_id;
    
    -- Obter o ID do usuário da sessão
    SELECT user_id INTO @user_id FROM quiz_sessions WHERE session_id = p_session_id;
    
    -- Registrar no log
    INSERT INTO activity_logs (user_id, action_type, action_description)
    VALUES (@user_id, 'COMPLETE_QUIZ', CONCAT('Concluiu quiz, sessão ID: ', p_session_id));
END//
DELIMITER ;

-- Procedimento para obter ranking global
DELIMITER //
CREATE PROCEDURE get_global_ranking(
    IN p_limit INT
)
BEGIN
    SELECT u.user_id, u.name, u.total_points, u.current_level, 
           l.level_name,
           COUNT(DISTINCT ub.badge_id) AS badges_count
    FROM users u
    LEFT JOIN levels l ON u.current_level = l.level_id
    LEFT JOIN user_badges ub ON u.user_id = ub.user_id
    WHERE u.is_active = TRUE
    GROUP BY u.user_id
    ORDER BY u.total_points DESC
    LIMIT p_limit;
END//
DELIMITER ;

-- Procedimento para obter ranking por categoria
DELIMITER //
CREATE PROCEDURE get_category_ranking(
    IN p_category_id INT,
    IN p_limit INT
)
BEGIN
    SELECT u.user_id, u.name, uc.points, u.current_level,
           l.level_name,
           uc.correct_answers, uc.questions_answered,
           ROUND((uc.correct_answers / uc.questions_answered) * 100, 2) AS accuracy
    FROM user_categories uc
    JOIN users u ON uc.user_id = u.user_id
    JOIN levels l ON u.current_level = l.level_id
    WHERE uc.category_id = p_category_id
      AND u.is_active = TRUE
    ORDER BY uc.points DESC
    LIMIT p_limit;
END//
DELIMITER ;

-- Procedimento para obter estatísticas do usuário
DELIMITER //
CREATE PROCEDURE get_user_statistics(
    IN p_user_id INT
)
BEGIN
    -- Estatísticas gerais
    SELECT 
        u.total_points,
        u.current_level,
        l.level_name,
        COUNT(DISTINCT ub.badge_id) AS total_badges,
        COUNT(DISTINCT qs.session_id) AS quizzes_completed,
        SUM(qs.accuracy_percentage) / COUNT(qs.session_id) AS average_accuracy
    FROM users u
    LEFT JOIN levels l ON u.current_level = l.level_id
    LEFT JOIN user_badges ub ON u.user_id = ub.user_id
    LEFT JOIN quiz_sessions qs ON u.user_id = qs.user_id AND qs.completed = TRUE
    WHERE u.user_id = p_user_id
    GROUP BY u.user_id;
    
    -- Estatísticas por categoria
    SELECT 
        c.name AS category,
        uc.points,
        uc.questions_answered,
        uc.correct_answers,
        ROUND((uc.correct_answers / uc.questions_answered) * 100, 2) AS accuracy
    FROM user_categories uc
    JOIN categories c ON uc.category_id = c.category_id
    WHERE uc.user_id = p_user_id
    ORDER BY uc.points DESC;
    
    -- Badges conquistadas
    SELECT 
        b.name, b.description, b.icon, ub.earned_at
    FROM user_badges ub
    JOIN badges b ON ub.badge_id = b.badge_id
    WHERE ub.user_id = p_user_id
    ORDER BY ub.earned_at DESC;
END//
DELIMITER ;

-- Procedimento para obter relatório de perguntas mais erradas
DELIMITER //
CREATE PROCEDURE get_most_failed_questions(
    IN p_limit INT
)
BEGIN
    SELECT 
        q.question_id,
        q.content,
        COUNT(ua.answer_id) AS total_attempts,
        SUM(IF(ua.is_correct = FALSE, 1, 0)) AS incorrect_attempts,
        ROUND((SUM(IF(ua.is_correct = FALSE, 1, 0)) / COUNT(ua.answer_id)) * 100, 2) AS failure_rate,
        c.name AS category,
        d.name AS difficulty
    FROM questions q
    JOIN user_answers ua ON q.question_id = ua.question_id
    JOIN categories c ON q.category_id = c.category_id
    JOIN difficulties d ON q.difficulty_id = d.difficulty_id
    GROUP BY q.question_id
    HAVING total_attempts >= 5 -- Mínimo de tentativas para ser significativo
    ORDER BY failure_rate DESC
    LIMIT p_limit;
END//
DELIMITER ;

-- Procedimento para obter desempenho médio por categoria
DELIMITER //
CREATE PROCEDURE get_category_performance()
BEGIN
    SELECT 
        c.name AS category,
        COUNT(DISTINCT ua.session_id) AS total_sessions,
        COUNT(ua.answer_id) AS total_questions,
        SUM(IF(ua.is_correct = TRUE, 1, 0)) AS correct_answers,
        ROUND((SUM(IF(ua.is_correct = TRUE, 1, 0)) / COUNT(ua.answer_id)) * 100, 2) AS accuracy,
        AVG(ua.points_earned) AS avg_points_per_question
    FROM categories c
    JOIN questions q ON c.category_id = q.category_id
    JOIN user_answers ua ON q.question_id = ua.question_id
    GROUP BY c.category_id
    ORDER BY accuracy DESC;
END//
DELIMITER ;

-- ==========================================
-- INSERTS INICIAIS
-- ==========================================

-- Inserir níveis
INSERT INTO levels (level_name, min_points, max_points, description) VALUES
('Iniciante', 0, 99, 'Começando a jornada em TI'),
('Aprendiz', 100, 499, 'Conhecimentos básicos adquiridos'),
('Desenvolvedor', 500, 999, 'Já domina conceitos importantes'),
('Especialista', 1000, 2499, 'Profundo conhecimento técnico'),
('Mestre', 2500, 4999, 'Domínio avançado dos conceitos'),
('Guru', 5000, 999999, 'Sabedoria suprema em TI');

-- Inserir categorias
INSERT INTO categories (name, description, icon) VALUES
('Python', 'Linguagem de programação Python e seus frameworks', 'python-icon'),
('SQL', 'Banco de dados e consultas SQL', 'sql-icon'),
('Redes', 'Protocolos e conceitos de redes de computadores', 'network-icon'),
('DevOps', 'Práticas e ferramentas de DevOps', 'devops-icon'),
('Frontend', 'Desenvolvimento web frontend', 'frontend-icon'),
('Backend', 'Desenvolvimento web backend', 'backend-icon'),
('Segurança', 'Segurança da informação e cibersegurança', 'security-icon'),
('Mobile', 'Desenvolvimento de aplicativos móveis', 'mobile-icon'),
('Teoria da Computação', 'Conceitos teóricos fundamentais', 'theory-icon'),
('Cloud', 'Computação em nuvem e serviços', 'cloud-icon');

-- Inserir dificuldades
INSERT INTO difficulties (name, points_multiplier, time_limit, description) VALUES
('Fácil', 1.0, 30, 'Perguntas básicas para iniciantes'),
('Médio', 1.5, 20, 'Conceitos intermediários'),
('Difícil', 2.0, 10, 'Perguntas avançadas para especialistas');

-- Inserir tipos de perguntas
INSERT INTO question_types (name, description) VALUES
('Múltipla Escolha', 'Pergunta com alternativas A, B, C, D'),
('Resposta Escrita', 'Pergunta que requer uma resposta textual');

-- Inserir badges/conquistas
INSERT INTO badges (name, description, icon, category_id, achievement_condition, achievement_threshold) VALUES
-- Badges gerais
('Primeiros Passos', 'Atingiu 100 pontos totais', 'steps-icon', NULL, 'total_points', 100),
('Dedicação', 'Completou 10 quizzes', 'quiz-icon', NULL, 'quizzes_completed', 10),
('Sem Erros', '5 respostas corretas consecutivas', 'streak-icon', NULL, 'consecutive_correct', 5),
('Mestre do Conhecimento', 'Atingiu 5000 pontos', 'master-icon', NULL, 'total_points', 5000),

-- Badges por categoria
('Pythonista', 'Atingiu 500 pontos em Python', 'python-badge', 1, 'points_in_category', 500),
('SQL Master', 'Atingiu 500 pontos em SQL', 'sql-badge', 2, 'points_in_category', 500),
('Especialista em Redes', 'Atingiu 500 pontos em Redes', 'network-badge', 3, 'points_in_category', 500),
('DevOps Profissional', 'Atingiu 500 pontos em DevOps', 'devops-badge', 4, 'points_in_category', 500),
('Frontend Developer', 'Atingiu 500 pontos em Frontend', 'frontend-badge', 5, 'points_in_category', 500),
'Backend Developer', 'Atingiu 500 pontos em Backend', 'backend-badge', 6, 'points_in_category', 500),
('Especialista em Segurança', 'Atingiu 500 pontos em Segurança', 'security-badge', 7, 'points_in_category', 500),
('Mobile Developer', 'Atingiu 500 pontos em Mobile', 'mobile-badge', 8, 'points_in_category', 500),
('Teórico', 'Atingiu 500 pontos em Teoria da Computação', 'theory-badge', 9, 'points_in_category', 500),
('Cloud Expert', 'Atingiu 500 pontos em Cloud', 'cloud-badge', 10, 'points_in_category', 500);

-- Inserir configurações do sistema
INSERT INTO system_settings (setting_key, setting_value, description) VALUES
('questions_per_quiz', '10', 'Número padrão de perguntas por quiz'),
('enable_timer', 'true', 'Habilitar temporizador para respostas'),
('consecutive_bonus_threshold', '3', 'Número de acertos consecutivos para bônus'),
('consecutive_bonus_percentage', '10', 'Porcentagem de bônus por acertos consecutivos'),
('time_bonus_percentage', '20', 'Porcentagem de bônus por resposta rápida'),
('time_bonus_threshold', '50', 'Porcentagem do tempo limite para ganhar bônus de tempo'),
('partial_match_enabled', 'true', 'Permitir correspondência parcial para respostas escritas'),
('ranking_limit', '10', 'Limite de usuários exibidos no ranking'),
('maintenance_mode', 'false', 'Sistema em manutenção');

-- ==========================================
-- FUNÇÕES
-- ==========================================

-- Função para calcular nível com base em pontos
DELIMITER //
CREATE FUNCTION calculate_level(p_points INT) RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE lvl_id INT;
    
    SELECT level_id INTO lvl_id
    FROM levels
    WHERE p_points BETWEEN min_points AND max_points
    LIMIT 1;
    
    RETURN lvl_id;
END//
DELIMITER ;

-- Função para verificar se o usuário tem uma badge específica
DELIMITER //
CREATE FUNCTION has_badge(p_user_id INT, p_badge_id INT) RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    DECLARE has_it BOOLEAN DEFAULT FALSE;
    
    SELECT EXISTS (
        SELECT 1 FROM user_badges 
        WHERE user_id = p_user_id AND badge_id = p_badge_id
    ) INTO has_it;
    
    RETURN has_it;
END//
DELIMITER ;

-- Função para calcular acurácia de um usuário em uma categoria
DELIMITER //
CREATE FUNCTION calculate_user_category_accuracy(p_user_id INT, p_category_id INT) RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
    DECLARE accuracy DECIMAL(5,2) DEFAULT 0;
    
    SELECT 
        IF(questions_answered > 0, 
           (correct_answers / questions_answered) * 100, 
           0) INTO accuracy
    FROM user_categories
    WHERE user_id = p_user_id AND category_id = p_category_id;
    
    RETURN accuracy;
END//
DELIMITER ;

-- ==========================================
-- VIEWS
-- ==========================================

-- View para ranking global
CREATE VIEW global_ranking AS
SELECT 
    u.user_id,
    u.name,
    u.total_points,
    u.current_level,
    l.level_name,
    (SELECT COUNT(*) FROM user_badges ub WHERE ub.user_id = u.user_id) AS badges_count
FROM users u
JOIN levels l ON u.current_level = l.level_id
WHERE u.is_active = TRUE
ORDER BY u.total_points DESC;

-- View para relatório de perguntas mais errradas
CREATE VIEW most_failed_questions AS
SELECT 
    q.question_id,
    q.content,
    COUNT(ua.answer_id) AS total_attempts,
    SUM(IF(ua.is_correct = FALSE, 1, 0)) AS incorrect_attempts,
    ROUND((SUM(IF(ua.is_correct = FALSE, 1, 0)) / COUNT(ua.answer_id)) * 100, 2) AS failure_rate,
    c.name AS category,
    d.name AS difficulty
FROM questions q
JOIN user_answers ua ON q.question_id = ua.question_id
JOIN categories c ON q.category_id = c.category_id
JOIN difficulties d ON q.difficulty_id = d.difficulty_id
GROUP BY q.question_id
HAVING total_attempts >= 5
ORDER BY failure_rate DESC;

-- View para desempenho por categoria
CREATE VIEW category_performance AS
SELECT 
    c.category_id,
    c.name AS category,
    COUNT(DISTINCT ua.session_id) AS total_sessions,
    COUNT(ua.answer_id) AS total_questions,
    SUM(IF(ua.is_correct = TRUE, 1, 0)) AS correct_answers,
    ROUND((SUM(IF(ua.is_correct = TRUE, 1, 0)) / COUNT(ua.answer_id)) * 100, 2) AS accuracy,
    AVG(ua.points_earned) AS avg_points_per_question
FROM categories c
JOIN questions q ON c.category_id = q.category_id
JOIN user_answers ua ON q.question_id = ua.question_id
GROUP BY c.category_id
ORDER BY accuracy DESC;

-- View para desempenho de usuários
CREATE VIEW user_performance AS
SELECT 
    u.user_id,
    u.name,
    u.total_points,
    l.level_name,
    COUNT(DISTINCT qs.session_id) AS quizzes_completed,
    COUNT(ua.answer_id) AS total_questions_answered,
    SUM(IF(ua.is_correct = TRUE, 1, 0)) AS correct_answers,
    ROUND((SUM(IF(ua.is_correct = TRUE, 1, 0)) / COUNT(ua.answer_id)) * 100, 2) AS overall_accuracy,
    (SELECT COUNT(*) FROM user_badges ub WHERE ub.user_id = u.user_id) AS badges_earned
FROM users u
LEFT JOIN levels l ON u.current_level = l.level_id
LEFT JOIN quiz_sessions qs ON u.user_id = qs.user_id AND qs.completed = TRUE
LEFT JOIN user_answers ua ON qs.session_id = ua.session_id
WHERE u.is_active = TRUE
GROUP BY u.user_id
ORDER BY u.total_points DESC;

-- ==========================================
-- ÍNDICES ADICIONAIS
-- ==========================================

-- Índice para otimizar pesquisas de perguntas por categoria e dificuldade
CREATE INDEX idx_questions_category_difficulty ON questions(category_id, difficulty_id, is_active);

-- Índice para otimizar consultas de respostas do usuário 
CREATE INDEX idx_user_answers_correctness ON user_answers(is_correct);

-- Índice para otimizar pesquisas de sessões por usuário
CREATE INDEX idx_quiz_sessions_user ON quiz_sessions(user_id, completed);

-- Índice para buscas de badges por condição e limite
CREATE INDEX idx_badges_condition ON badges(achievement_condition, achievement_threshold);

-- Índice para buscas no log de atividades por data
CREATE INDEX idx_activity_logs_date ON activity_logs(created_at);

-- ==========================================
-- EXEMPLO DE DADOS PARA TESTES
-- ==========================================

-- Usuário admin (senha: admin123)
INSERT INTO users (name, email, password_hash, is_admin, is_active) VALUES
('Administrador', 'admin@quizti.com', '$2y$10$GCvlN.U2LO2e6YFNRkTkU.7jW6q.YAjDLTLGrNhRKORYS7d5cxvlu', TRUE, TRUE);

-- Usuários comuns (senha: user123)
INSERT INTO users (name, email, password_hash, is_active) VALUES
('João Silva', 'joao@example.com', '$2y$10$7iGQkt30QsvuU1cIBl3W3.TqI2O7sZRYjfUkElGfxP3gVkzEwcQfK', TRUE),
('Maria Oliveira', 'maria@example.com', '$2y$10$7iGQkt30QsvuU1cIBl3W3.TqI2O7sZRYjfUkElGfxP3gVkzEwcQfK', TRUE),
('Carlos Santos', 'carlos@example.com', '$2y$10$7iGQkt30QsvuU1cIBl3W3.TqI2O7sZRYjfUkElGfxP3gVkzEwcQfK', TRUE);

-- Perguntas de Python (categoria_id=1)
INSERT INTO questions (content, category_id, difficulty_id, type_id, base_points, created_by) VALUES
('Qual é a função utilizada para imprimir texto no console em Python?', 1, 1, 1, 10, 1),
('Como se declara uma lista vazia em Python?', 1, 1, 1, 10, 1),
('Qual método é utilizado para adicionar um elemento ao final de uma lista em Python?', 1, 1, 1, 10, 1),
('O que é o PEP 8?', 1, 2, 1, 20, 1),
('Explique o conceito de "compreensão de lista" (list comprehension) em Python.', 1, 2, 2, 20, 1),
('Qual é a diferença entre __str__ e __repr__ em Python?', 1, 3, 2, 30, 1);

-- Alternativas para perguntas de múltipla escolha
-- Pergunta 1
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(1, 'print()', TRUE),
(1, 'echo()', FALSE),
(1, 'console.log()', FALSE),
(1, 'write()', FALSE);

-- Pergunta 2
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(2, '[]', TRUE),
(2, '{}', FALSE),
(2, '()', FALSE),
(2, 'list()', TRUE);

-- Pergunta 3
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(3, 'append()', TRUE),
(3, 'insert()', FALSE),
(3, 'add()', FALSE),
(3, 'push()', FALSE);

-- Pergunta 4
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(4, 'Guia de estilo para código Python', TRUE),
(4, 'Processador de texto para Python', FALSE),
(4, 'Biblioteca de análise de dados', FALSE),
(4, 'Ferramenta de compilação Python', FALSE);

-- Respostas escritas
INSERT INTO written_answers (question_id, correct_answer, alternative_answers) VALUES
(5, 'Uma maneira concisa de criar listas baseadas em sequências existentes', 'List comprehension|Forma compacta de criar listas|Sintaxe para criar listas de forma concisa'),
(6, 'O método __str__ é para representação legível por humanos e __repr__ é para representação não ambígua que poderia ser usada para recriar o objeto', '__str__ para impressão amigável, __repr__ para debug e desenvolvimento|__str__ é informal e __repr__ é formal e preciso');

-- Perguntas de SQL (categoria_id=2)
INSERT INTO questions (content, category_id, difficulty_id, type_id, base_points, created_by) VALUES
('Qual comando SQL é utilizado para selecionar dados de uma tabela?', 2, 1, 1, 10, 1),
('O que significa a sigla SQL?', 2, 1, 1, 10, 1),
('Qual é a diferença entre INNER JOIN e LEFT JOIN?', 2, 2, 2, 20, 1);

-- Alternativas para perguntas de SQL
-- Pergunta 7
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(7, 'SELECT', TRUE),
(7, 'FETCH', FALSE),
(7, 'GET', FALSE),
(7, 'EXTRACT', FALSE);

-- Pergunta 8
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(8, 'Structured Query Language', TRUE),
(8, 'Simple Query Language', FALSE),
(8, 'Standard Query Logic', FALSE),
(8, 'System Query Language', FALSE);

-- Respostas escritas para SQL
INSERT INTO written_answers (question_id, correct_answer, alternative_answers) VALUES
(9, 'INNER JOIN retorna apenas registros com correspondências em ambas as tabelas, enquanto LEFT JOIN retorna todos os registros da tabela à esquerda e os registros correspondentes da tabela à direita', 'INNER JOIN mostra apenas correspondências, LEFT JOIN mostra todos da tabela da esquerda|INNER JOIN combina apenas registros correspondentes, LEFT JOIN preserva todos os registros da primeira tabela');

-- Perguntas de Redes (categoria_id=3)
INSERT INTO questions (content, category_id, difficulty_id, type_id, base_points, created_by) VALUES
('Qual protocolo é utilizado para transferência de arquivos na internet?', 3, 1, 1, 10, 1),
('O que é um endereço IP?', 3, 1, 2, 10, 1),
('Complete: O protocolo _____ é usado para envio de e-mails.', 3, 2, 2, 20, 1);

-- Alternativas para pergunta de Redes
-- Pergunta 10
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(10, 'FTP', TRUE),
(10, 'HTTP', FALSE),
(10, 'SMTP', FALSE),
(10, 'SSH', FALSE);

-- Respostas escritas para Redes
INSERT INTO written_answers (question_id, correct_answer, alternative_answers) VALUES
(11, 'Um identificador numérico atribuído a cada dispositivo conectado a uma rede que utiliza o protocolo IP', 'Número que identifica um dispositivo na rede|Endereço numérico de um computador ou dispositivo em uma rede'),
(12, 'SMTP', 'Simple Mail Transfer Protocol');

-- ==========================================
-- EVENTOS
-- ==========================================

-- Evento para limpar tokens de redefinição de senha expirados
DELIMITER //
CREATE EVENT clean_expired_reset_tokens
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
  DELETE FROM users 
  WHERE reset_token_expires IS NOT NULL 
  AND reset_token_expires < NOW();
END//
DELIMITER ;

-- Evento para atualizar estatísticas do sistema
DELIMITER //
CREATE EVENT update_system_statistics
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
  -- Atualizar contagem total de perguntas respondidas
  SELECT COUNT(*) INTO @total_answers FROM user_answers;
  
  -- Atualizar taxa de acerto global
  SELECT 
    ROUND((SUM(IF(is_correct = TRUE, 1, 0)) / COUNT(*)) * 100, 2) 
  INTO @global_accuracy 
  FROM user_answers;
  
  -- Registrar estatísticas
  INSERT INTO system_settings (setting_key, setting_value, description)
  VALUES 
    ('total_answers', @total_answers, 'Total de respostas registradas no sistema')
  ON DUPLICATE KEY UPDATE 
    setting_value = @total_answers;
    
  INSERT INTO system_settings (setting_key, setting_value, description)
  VALUES 
    ('global_accuracy', @global_accuracy, 'Taxa de acerto global dos usuários')
  ON DUPLICATE KEY UPDATE 
    setting_value = @global_accuracy;
END//
DELIMITER ;

-- ==========================================
-- RESTRIÇÕES ADICIONAIS
-- ==========================================

-- Verificar que a dificuldade é válida
ALTER TABLE questions
ADD CONSTRAINT chk_difficulty 
CHECK (difficulty_id IN (1, 2, 3));

-- Verificar que o tipo de pergunta é válido
ALTER TABLE questions
ADD CONSTRAINT chk_question_type 
CHECK (type_id IN (1, 2));

-- Garantir que os pontos base são positivos
ALTER TABLE questions
ADD CONSTRAINT chk_base_points 
CHECK (base_points > 0);

-- ==========================================
-- COMENTÁRIOS NAS TABELAS
-- ==========================================

ALTER TABLE users COMMENT 'Armazena informações dos usuários, incluindo administradores';
ALTER TABLE levels COMMENT 'Define os níveis disponíveis e intervalos de pontos necessários';
ALTER TABLE categories COMMENT 'Categorias de perguntas disponíveis no sistema';
ALTER TABLE difficulties COMMENT 'Níveis de dificuldade das perguntas (fácil, médio, difícil)';
ALTER TABLE question_types COMMENT 'Tipos de perguntas suportados pelo sistema';
ALTER TABLE questions COMMENT 'Banco de perguntas com categoria, dificuldade e tipo';
ALTER TABLE alternatives COMMENT 'Alternativas para perguntas de múltipla escolha';
ALTER TABLE written_answers COMMENT 'Respostas corretas para perguntas de texto livre';
ALTER TABLE quiz_sessions COMMENT 'Registra cada sessão de quiz iniciada por um usuário';
ALTER TABLE user_answers COMMENT 'Histórico de respostas dos usuários';
ALTER TABLE badges COMMENT 'Conquistas que podem ser desbloqueadas pelos usuários';
ALTER TABLE user_badges COMMENT 'Registro de badges conquistadas por cada usuário';
ALTER TABLE user_categories COMMENT 'Pontuação de usuários por categoria';
ALTER TABLE system_settings COMMENT 'Configurações globais do sistema';
ALTER TABLE activity_logs COMMENT 'Registro de atividades dos usuários no sistema';

-- ==========================================
-- PERMISSÕES
-- ==========================================

-- Criação de usuário para a aplicação web
CREATE USER IF NOT EXISTS 'quiz_app'@'localhost' IDENTIFIED BY 'secure_password_here';

-- Conceder permissões necessárias
GRANT SELECT, INSERT, UPDATE, DELETE ON quiz_ti.* TO 'quiz_app'@'localhost';

-- Criação de usuário somente leitura (para relatórios)
CREATE USER IF NOT EXISTS 'quiz_reader'@'localhost' IDENTIFIED BY 'read_only_password';

-- Conceder permissões de leitura apenas
GRANT SELECT ON quiz_ti.* TO 'quiz_reader'@'localhost';

-- Revogar acesso direto às tabelas sensíveis para o usuário de leitura
REVOKE SELECT ON quiz_ti.users FROM 'quiz_reader'@'localhost';

-- ==========================================
-- FINALIZAÇÃO
-- ==========================================

-- Aplicar alterações
FLUSH PRIVILEGES;

-- Mensagem de conclusão
SELECT 'Banco de dados da aplicação Quiz em TI criado com sucesso!' AS 'Status';
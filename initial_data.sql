-- Criar usuário administrador
INSERT INTO users (name, email, password_hash, is_admin, is_active) VALUES 
('Administrador', 'admin@quizti.com', '$2b$12$/eYGP/GSCQqM2CqApZhHGOkz4o1V7X45AzHieNDAZrGtkL5ocFNJC', TRUE, TRUE);

-- Inserir categorias básicas
INSERT INTO categories (name, description, icon) VALUES
('Python', 'Linguagem de programação Python e seus frameworks', 'fab fa-python'),
('SQL', 'Banco de dados e consultas SQL', 'fas fa-database'),
('Redes', 'Protocolos e conceitos de redes de computadores', 'fas fa-network-wired'),
('DevOps', 'Práticas e ferramentas de DevOps', 'fas fa-infinity'),
('Frontend', 'Desenvolvimento web frontend', 'fas fa-code'),
('Backend', 'Desenvolvimento web backend', 'fas fa-server'),
('Segurança', 'Segurança da informação e cibersegurança', 'fas fa-shield-alt'),
('Mobile', 'Desenvolvimento de aplicativos móveis', 'fas fa-mobile-alt'),
('Cloud', 'Computação em nuvem e serviços', 'fas fa-cloud');

-- Inserir níveis de dificuldade
INSERT INTO difficulties (name, points_multiplier, time_limit, description) VALUES
('Fácil', 1.0, 30, 'Perguntas básicas para iniciantes'),
('Médio', 1.5, 20, 'Conceitos intermediários'),
('Difícil', 2.0, 10, 'Perguntas avançadas para especialistas');

-- Inserir tipos de perguntas
INSERT INTO question_types (name, description) VALUES
('Múltipla Escolha', 'Pergunta com alternativas A, B, C, D'),
('Resposta Escrita', 'Pergunta que requer uma resposta textual');

-- Inserir algumas perguntas de exemplo
INSERT INTO questions (content, category_id, difficulty_id, type_id, base_points, created_by) VALUES
('Qual é a função utilizada para imprimir texto no console em Python?', 1, 1, 1, 10, 1),
('O que significa SQL?', 2, 1, 1, 10, 1),
('Qual protocolo é utilizado para transferência de páginas web?', 3, 1, 1, 10, 1);

-- Inserir alternativas para as perguntas
INSERT INTO alternatives (question_id, content, is_correct) VALUES
(1, 'print()', TRUE),
(1, 'echo()', FALSE),
(1, 'console.log()', FALSE),
(1, 'write()', FALSE);

INSERT INTO alternatives (question_id, content, is_correct) VALUES
(2, 'Structured Query Language', TRUE),
(2, 'Simple Query Language', FALSE),
(2, 'Standard Query Logic', FALSE),
(2, 'System Query Language', FALSE);

INSERT INTO alternatives (question_id, content, is_correct) VALUES
(3, 'HTTP', TRUE),
(3, 'FTP', FALSE),
(3, 'SMTP', FALSE),
(3, 'SSH', FALSE);

-- Inserir badges iniciais
INSERT INTO badges (name, description, icon, achievement_condition, achievement_threshold) VALUES
('Iniciante', 'Completou seu primeiro quiz', 'fas fa-star', 'quizzes_completed', 1),
('Estudioso', 'Completou 10 quizzes', 'fas fa-book', 'quizzes_completed', 10),
('Mestre', 'Atingiu 1000 pontos', 'fas fa-crown', 'total_points', 1000),
('Especialista Python', 'Atingiu 500 pontos em Python', 'fab fa-python', 'points_in_category', 500),
('Especialista SQL', 'Atingiu 500 pontos em SQL', 'fas fa-database', 'points_in_category', 500),
('Especialista Redes', 'Atingiu 500 pontos em Redes', 'fas fa-network-wired', 'points_in_category', 500); 
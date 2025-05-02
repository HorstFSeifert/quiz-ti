-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Tempo de geração: 22/04/2025 às 20:09
-- Versão do servidor: 10.4.32-MariaDB
-- Versão do PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Banco de dados: `quiz_ti`
--

DELIMITER $$
--
-- Procedimentos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `complete_quiz_session` (IN `p_session_id` INT)   BEGIN
    UPDATE quiz_sessions
    SET completed = TRUE
    WHERE session_id = p_session_id;
    
    -- Obter o ID do usuário da sessão
    SELECT user_id INTO @user_id FROM quiz_sessions WHERE session_id = p_session_id;
    
    -- Registrar no log
    INSERT INTO activity_logs (user_id, action_type, action_description)
    VALUES (@user_id, 'COMPLETE_QUIZ', CONCAT('Concluiu quiz, sessão ID: ', p_session_id));
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_category_performance` ()   BEGIN
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
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_category_ranking` (IN `p_category_id` INT, IN `p_limit` INT)   BEGIN
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
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_global_ranking` (IN `p_limit` INT)   BEGIN
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
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_most_failed_questions` (IN `p_limit` INT)   BEGIN
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
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_question_alternatives` (IN `p_question_id` INT)   BEGIN
    SELECT alternative_id, content
    FROM alternatives
    WHERE question_id = p_question_id
    ORDER BY RAND(); -- Aleatorizar a ordem das alternativas
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_quiz_questions` (IN `p_user_id` INT, IN `p_category_id` INT, IN `p_difficulty_id` INT, IN `p_limit` INT)   BEGIN
    -- Seleciona questões que:
    -- 1. Não foram respondidas pelo usuário
    -- 2. Não estão bloqueadas
    -- 3. Estão ativas
    SELECT DISTINCT 
        q.question_id, 
        q.content, 
        q.type_id, 
        q.base_points,
        d.time_limit
    FROM questions q
    JOIN difficulties d ON q.difficulty_id = d.difficulty_id
    WHERE q.category_id = p_category_id
    AND q.difficulty_id = p_difficulty_id
    AND q.is_active = TRUE
    AND NOT EXISTS (
        -- Verifica se o usuário já respondeu esta questão
        SELECT 1 
        FROM user_answers ua
        JOIN quiz_sessions qs ON ua.session_id = qs.session_id
        WHERE qs.user_id = p_user_id
        AND ua.question_id = q.question_id
    )
    AND NOT EXISTS (
        -- Verifica se a questão está bloqueada
        SELECT 1 
        FROM user_question_blocks uqb
        WHERE uqb.user_id = p_user_id
        AND uqb.question_id = q.question_id
        AND uqb.blocked_until > NOW()
    )
    ORDER BY RAND()
    LIMIT p_limit;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `get_user_statistics` (IN `p_user_id` INT)   BEGIN
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
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `save_user_answer` (IN `p_session_id` INT, IN `p_question_id` INT, IN `p_alternative_id` INT, IN `p_written_response` TEXT, IN `p_response_time` INT)   BEGIN
    -- A verificação da resposta e cálculo de pontos é feito por triggers
    INSERT INTO user_answers (session_id, question_id, alternative_id, written_response, response_time)
    VALUES (p_session_id, p_question_id, p_alternative_id, p_written_response, p_response_time);
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `start_quiz_session` (IN `p_user_id` INT, IN `p_category_id` INT, IN `p_difficulty_id` INT, OUT `p_session_id` INT)   BEGIN
    INSERT INTO quiz_sessions (user_id, category_id, difficulty_id)
    VALUES (p_user_id, p_category_id, p_difficulty_id);
    
    SET p_session_id = LAST_INSERT_ID();
    
    -- Registrar no log
    INSERT INTO activity_logs (user_id, action_type, action_description)
    VALUES (p_user_id, 'START_QUIZ', CONCAT('Iniciou quiz na categoria ', p_category_id, ' com dificuldade ', p_difficulty_id));
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `update_question_start_time` (IN `p_session_id` INT)   BEGIN
    UPDATE quiz_sessions 
    SET current_question_start = NOW()
    WHERE session_id = p_session_id;
END$$

--
-- Funções
--
CREATE DEFINER=`root`@`localhost` FUNCTION `calculate_level` (`p_points` INT) RETURNS INT(11) DETERMINISTIC BEGIN
    DECLARE lvl_id INT;
    
    SELECT level_id INTO lvl_id
    FROM levels
    WHERE p_points BETWEEN min_points AND max_points
    LIMIT 1;
    
    RETURN lvl_id;
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `calculate_user_category_accuracy` (`p_user_id` INT, `p_category_id` INT) RETURNS DECIMAL(5,2) DETERMINISTIC BEGIN
    DECLARE accuracy DECIMAL(5,2) DEFAULT 0;
    
    SELECT 
        IF(questions_answered > 0, 
           (correct_answers / questions_answered) * 100, 
           0) INTO accuracy
    FROM user_categories
    WHERE user_id = p_user_id AND category_id = p_category_id;
    
    RETURN accuracy;
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `has_badge` (`p_user_id` INT, `p_badge_id` INT) RETURNS TINYINT(1) DETERMINISTIC BEGIN
    DECLARE has_it BOOLEAN DEFAULT FALSE;
    
    SELECT EXISTS (
        SELECT 1 FROM user_badges 
        WHERE user_id = p_user_id AND badge_id = p_badge_id
    ) INTO has_it;
    
    RETURN has_it;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estrutura para tabela `activity_logs`
--

CREATE TABLE `activity_logs` (
  `log_id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `action_type` varchar(50) NOT NULL,
  `action_description` text NOT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `activity_logs`
--

INSERT INTO `activity_logs` (`log_id`, `user_id`, `action_type`, `action_description`, `ip_address`, `created_at`) VALUES
(1, 1, 'USER_REGISTER', 'Novo usuário registrado: Horst Fernandes Seifert', NULL, '2025-04-22 14:59:13'),
(2, 2, 'USER_REGISTER', 'Novo usuário registrado: Administrador', NULL, '2025-04-22 15:35:46'),
(3, 3, 'USER_REGISTER', 'Novo usuário registrado:   ', NULL, '2025-04-22 17:03:17'),
(4, 4, 'USER_REGISTER', 'Novo usuário registrado: pedro', NULL, '2025-04-22 17:06:01'),
(5, 5, 'USER_REGISTER', 'Novo usuário registrado: a', NULL, '2025-04-22 17:11:34');

-- --------------------------------------------------------

--
-- Estrutura para tabela `alternatives`
--

CREATE TABLE `alternatives` (
  `alternative_id` int(11) NOT NULL,
  `question_id` int(11) NOT NULL,
  `content` text NOT NULL,
  `is_correct` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `alternatives`
--

INSERT INTO `alternatives` (`alternative_id`, `question_id`, `content`, `is_correct`) VALUES
(1, 1, 'Teste 1 correta', 1),
(2, 1, 'teste 2 incorreta', 0),
(3, 1, 'teste 3 incorreta', 0),
(4, 1, 'teste 4 incorreta', 0),
(5, 2, 'print()', 1),
(6, 2, 'console.log()', 0),
(7, 2, 'echo', 0),
(8, 2, 'System.out.println()', 0),
(9, 3, 'Uma forma concisa de criar listas baseada em listas existentes', 1),
(10, 3, 'Uma função para ordenar listas', 0),
(11, 3, 'Um método para concatenar listas', 0),
(12, 3, 'Uma biblioteca para manipulação de listas', 0),
(13, 4, '__str__ é para exibição legível e __repr__ é para representação não ambígua do objeto', 1),
(14, 4, 'São métodos idênticos com nomes diferentes', 0),
(15, 4, '__str__ é para debug e __repr__ é para usuários', 0),
(16, 4, 'Não há diferença, ambos são deprecados', 0),
(17, 5, 'SELECT', 1),
(18, 5, 'SHOW', 0),
(19, 5, 'GET', 0),
(20, 5, 'EXTRACT', 0),
(21, 6, 'INNER JOIN retorna apenas correspondências, LEFT JOIN inclui todos os registros da tabela à esquerda', 1),
(22, 6, 'São sinônimos, não há diferença', 0),
(23, 6, 'LEFT JOIN é mais rápido que INNER JOIN', 0),
(24, 6, 'INNER JOIN é usado apenas para chaves primárias', 0),
(25, 7, 'Uma subconsulta que referencia colunas da consulta externa', 1),
(26, 7, 'Uma consulta que usa apenas JOIN', 0),
(27, 7, 'Uma consulta que retorna apenas valores únicos', 0),
(28, 7, 'Uma consulta que usa apenas funções de agregação', 0),
(37, 10, 'HTTP', 1),
(38, 10, 'FTP', 0),
(39, 10, 'SMTP', 0),
(40, 10, 'SSH', 0),
(41, 11, 'Um identificador único de hardware para interfaces de rede', 1),
(42, 11, 'Um tipo de endereço IP', 0),
(43, 11, 'Um protocolo de roteamento', 0),
(44, 11, 'Um tipo de firewall', 0),
(45, 12, 'Um protocolo de roteamento entre sistemas autônomos na Internet', 1),
(46, 12, 'Um tipo de firewall de borda', 0),
(47, 12, 'Um protocolo de criptografia', 0),
(48, 12, 'Um sistema de cache de DNS', 0),
(49, 13, 'Uma plataforma para desenvolvimento, envio e execução de aplicações em contêineres', 1),
(50, 13, 'Um sistema operacional Linux', 0),
(51, 13, 'Uma linguagem de programação', 0),
(52, 13, 'Um servidor web', 0),
(53, 14, 'Prática de integrar mudanças de código frequentemente com testes automatizados', 1),
(54, 14, 'Um tipo de servidor de produção', 0),
(55, 14, 'Uma ferramenta de backup', 0),
(56, 14, 'Um método de criptografia de dados', 0);

-- --------------------------------------------------------

--
-- Estrutura para tabela `badges`
--

CREATE TABLE `badges` (
  `badge_id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(255) NOT NULL,
  `icon` varchar(100) DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `achievement_condition` varchar(255) NOT NULL,
  `achievement_threshold` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `badges`
--

INSERT INTO `badges` (`badge_id`, `name`, `description`, `icon`, `category_id`, `achievement_condition`, `achievement_threshold`) VALUES
(1, 'Iniciante', 'Atingiu 100 pontos totais', 'fas fa-star', NULL, 'total_points', 100),
(2, 'Dedicado', 'Completou 10 quizzes', 'fas fa-trophy', NULL, 'quizzes_completed', 10),
(3, 'Mestre', 'Atingiu 1000 pontos totais', 'fas fa-crown', NULL, 'total_points', 1000),
(4, 'Expert', 'Acertou 50 questões consecutivas', 'fas fa-award', NULL, 'consecutive_correct', 50),
(5, 'Novato em Backend', 'Atingiu 100 pontos em Backend', 'fas fa-medal', 6, 'points_in_category', 100),
(6, 'Especialista em Backend', 'Atingiu 500 pontos em Backend', 'fas fa-certificate', 6, 'points_in_category', 500),
(7, 'Mestre em Backend', 'Atingiu 1000 pontos em Backend', 'fas fa-star', 6, 'points_in_category', 1000),
(8, 'Novato em Cloud', 'Atingiu 100 pontos em Cloud', 'fas fa-medal', 10, 'points_in_category', 100),
(9, 'Especialista em Cloud', 'Atingiu 500 pontos em Cloud', 'fas fa-certificate', 10, 'points_in_category', 500),
(10, 'Mestre em Cloud', 'Atingiu 1000 pontos em Cloud', 'fas fa-star', 10, 'points_in_category', 1000),
(11, 'Novato em DevOps', 'Atingiu 100 pontos em DevOps', 'fas fa-medal', 4, 'points_in_category', 100),
(12, 'Especialista em DevOps', 'Atingiu 500 pontos em DevOps', 'fas fa-certificate', 4, 'points_in_category', 500),
(13, 'Mestre em DevOps', 'Atingiu 1000 pontos em DevOps', 'fas fa-star', 4, 'points_in_category', 1000),
(14, 'Novato em Frontend', 'Atingiu 100 pontos em Frontend', 'fas fa-medal', 5, 'points_in_category', 100),
(15, 'Especialista em Frontend', 'Atingiu 500 pontos em Frontend', 'fas fa-certificate', 5, 'points_in_category', 500),
(16, 'Mestre em Frontend', 'Atingiu 1000 pontos em Frontend', 'fas fa-star', 5, 'points_in_category', 1000),
(17, 'Novato em Mobile', 'Atingiu 100 pontos em Mobile', 'fas fa-medal', 8, 'points_in_category', 100),
(18, 'Especialista em Mobile', 'Atingiu 500 pontos em Mobile', 'fas fa-certificate', 8, 'points_in_category', 500),
(19, 'Mestre em Mobile', 'Atingiu 1000 pontos em Mobile', 'fas fa-star', 8, 'points_in_category', 1000),
(20, 'Novato em Python', 'Atingiu 100 pontos em Python', 'fas fa-medal', 1, 'points_in_category', 100),
(21, 'Especialista em Python', 'Atingiu 500 pontos em Python', 'fas fa-certificate', 1, 'points_in_category', 500),
(22, 'Mestre em Python', 'Atingiu 1000 pontos em Python', 'fas fa-star', 1, 'points_in_category', 1000),
(23, 'Novato em Redes', 'Atingiu 100 pontos em Redes', 'fas fa-medal', 3, 'points_in_category', 100),
(24, 'Especialista em Redes', 'Atingiu 500 pontos em Redes', 'fas fa-certificate', 3, 'points_in_category', 500),
(25, 'Mestre em Redes', 'Atingiu 1000 pontos em Redes', 'fas fa-star', 3, 'points_in_category', 1000),
(26, 'Novato em Segurança', 'Atingiu 100 pontos em Segurança', 'fas fa-medal', 7, 'points_in_category', 100),
(27, 'Especialista em Segurança', 'Atingiu 500 pontos em Segurança', 'fas fa-certificate', 7, 'points_in_category', 500),
(28, 'Mestre em Segurança', 'Atingiu 1000 pontos em Segurança', 'fas fa-star', 7, 'points_in_category', 1000),
(29, 'Novato em SQL', 'Atingiu 100 pontos em SQL', 'fas fa-medal', 2, 'points_in_category', 100),
(30, 'Especialista em SQL', 'Atingiu 500 pontos em SQL', 'fas fa-certificate', 2, 'points_in_category', 500),
(31, 'Mestre em SQL', 'Atingiu 1000 pontos em SQL', 'fas fa-star', 2, 'points_in_category', 1000),
(32, 'Novato em Teoria da Computação', 'Atingiu 100 pontos em Teoria da Computação', 'fas fa-medal', 9, 'points_in_category', 100),
(33, 'Especialista em Teoria da Computação', 'Atingiu 500 pontos em Teoria da Computação', 'fas fa-certificate', 9, 'points_in_category', 500),
(34, 'Mestre em Teoria da Computação', 'Atingiu 1000 pontos em Teoria da Computação', 'fas fa-star', 9, 'points_in_category', 1000);

-- --------------------------------------------------------

--
-- Estrutura para tabela `categories`
--

CREATE TABLE `categories` (
  `category_id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `icon` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `categories`
--

INSERT INTO `categories` (`category_id`, `name`, `description`, `icon`) VALUES
(1, 'Python', 'Linguagem de programação Python e seus frameworks', 'python-icon'),
(2, 'SQL', 'Banco de dados e consultas SQL', 'sql-icon'),
(3, 'Redes', 'Protocolos e conceitos de redes de computadores', 'network-icon'),
(4, 'DevOps', 'Práticas e ferramentas de DevOps', 'devops-icon'),
(5, 'Frontend', 'Desenvolvimento web frontend', 'frontend-icon'),
(6, 'Backend', 'Desenvolvimento web backend', 'backend-icon'),
(7, 'Segurança', 'Segurança da informação e cibersegurança', 'security-icon'),
(8, 'Mobile', 'Desenvolvimento de aplicativos móveis', 'mobile-icon'),
(9, 'Teoria da Computação', 'Conceitos teóricos fundamentais', 'theory-icon'),
(10, 'Cloud', 'Computação em nuvem e serviços', 'cloud-icon');

-- --------------------------------------------------------

--
-- Estrutura stand-in para view `category_performance`
-- (Veja abaixo para a visão atual)
--
CREATE TABLE `category_performance` (
`category_id` int(11)
,`category` varchar(50)
,`total_sessions` bigint(21)
,`total_questions` bigint(21)
,`correct_answers` decimal(22,0)
,`accuracy` decimal(28,2)
,`avg_points_per_question` decimal(14,4)
);

-- --------------------------------------------------------

--
-- Estrutura para tabela `difficulties`
--

CREATE TABLE `difficulties` (
  `difficulty_id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `points_multiplier` decimal(3,1) NOT NULL,
  `time_limit` int(11) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `difficulties`
--

INSERT INTO `difficulties` (`difficulty_id`, `name`, `points_multiplier`, `time_limit`, `description`) VALUES
(1, 'Fácil', 1.0, 30, 'Perguntas básicas para iniciantes'),
(2, 'Médio', 1.5, 20, 'Conceitos intermediários'),
(3, 'Difícil', 2.0, 10, 'Perguntas avançadas para especialistas');

-- --------------------------------------------------------

--
-- Estrutura stand-in para view `global_ranking`
-- (Veja abaixo para a visão atual)
--
CREATE TABLE `global_ranking` (
`user_id` int(11)
,`name` varchar(100)
,`total_points` int(11)
,`current_level` int(11)
,`level_name` varchar(50)
,`badges_count` bigint(21)
);

-- --------------------------------------------------------

--
-- Estrutura para tabela `levels`
--

CREATE TABLE `levels` (
  `level_id` int(11) NOT NULL,
  `level_name` varchar(50) NOT NULL,
  `min_points` int(11) NOT NULL,
  `max_points` int(11) NOT NULL,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `levels`
--

INSERT INTO `levels` (`level_id`, `level_name`, `min_points`, `max_points`, `description`) VALUES
(1, 'Iniciante', 0, 99, 'Começando a jornada em TI'),
(2, 'Aprendiz', 100, 499, 'Conhecimentos básicos adquiridos'),
(3, 'Desenvolvedor', 500, 999, 'Já domina conceitos importantes'),
(4, 'Especialista', 1000, 2499, 'Profundo conhecimento técnico'),
(5, 'Mestre', 2500, 4999, 'Domínio avançado dos conceitos'),
(6, 'Guru', 5000, 999999, 'Sabedoria suprema em TI');

-- --------------------------------------------------------

--
-- Estrutura stand-in para view `most_failed_questions`
-- (Veja abaixo para a visão atual)
--
CREATE TABLE `most_failed_questions` (
`question_id` int(11)
,`content` text
,`total_attempts` bigint(21)
,`incorrect_attempts` decimal(22,0)
,`failure_rate` decimal(28,2)
,`category` varchar(50)
,`difficulty` varchar(50)
);

-- --------------------------------------------------------

--
-- Estrutura para tabela `questions`
--

CREATE TABLE `questions` (
  `question_id` int(11) NOT NULL,
  `content` text NOT NULL,
  `category_id` int(11) NOT NULL,
  `difficulty_id` int(11) NOT NULL,
  `type_id` int(11) NOT NULL,
  `base_points` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `created_by` int(11) NOT NULL,
  `is_active` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `questions`
--

INSERT INTO `questions` (`question_id`, `content`, `category_id`, `difficulty_id`, `type_id`, `base_points`, `created_at`, `created_by`, `is_active`) VALUES
(1, 'Enunciado Teste 1 python', 1, 1, 1, 10, '2025-04-22 15:55:26', 2, 1),
(2, 'Qual é a função utilizada para imprimir texto no console em Python?', 1, 1, 1, 10, '2025-04-22 16:32:02', 2, 1),
(3, 'O que é uma list comprehension em Python?', 1, 2, 1, 20, '2025-04-22 16:35:17', 2, 1),
(4, 'Qual é a diferença entre __str__ e __repr__ em Python?', 1, 3, 1, 30, '2025-04-22 16:35:17', 2, 1),
(5, 'Qual comando SQL é usado para selecionar dados de uma tabela?', 2, 1, 1, 10, '2025-04-22 16:35:17', 2, 1),
(6, 'Qual é a diferença entre INNER JOIN e LEFT JOIN?', 2, 2, 1, 20, '2025-04-22 16:35:17', 2, 1),
(7, 'O que é uma subconsulta correlacionada em SQL?', 2, 3, 1, 30, '2025-04-22 16:35:18', 2, 1),
(8, 'Qual protocolo é usado para transferência de páginas web?', 3, 1, 1, 10, '2025-04-22 16:41:29', 2, 1),
(9, 'Qual protocolo é usado para transferência de páginas web?', 3, 1, 1, 10, '2025-04-22 16:41:34', 2, 1),
(10, 'Qual protocolo é usado para transferência de páginas web?', 3, 1, 1, 10, '2025-04-22 16:44:05', 2, 1),
(11, 'O que é um endereço MAC?', 3, 2, 1, 20, '2025-04-22 16:44:05', 2, 1),
(12, 'O que é BGP (Border Gateway Protocol)?', 3, 3, 1, 30, '2025-04-22 16:44:05', 2, 1),
(13, 'O que é Docker?', 4, 1, 1, 10, '2025-04-22 16:44:05', 2, 1),
(14, 'O que é Integração Contínua (CI)?', 4, 2, 1, 20, '2025-04-22 16:44:05', 2, 1),
(15, 'Qual é a função principal do CSS em uma página web?', 5, 1, 1, 10, '2025-04-22 16:47:37', 2, 1);

-- --------------------------------------------------------

--
-- Estrutura para tabela `question_feedback`
--

CREATE TABLE `question_feedback` (
  `question_id` int(11) NOT NULL,
  `correct_feedback` text NOT NULL,
  `incorrect_feedback` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `question_feedback`
--

INSERT INTO `question_feedback` (`question_id`, `correct_feedback`, `incorrect_feedback`) VALUES
(1, 'a resposta Teste 1 é a correta ! parabens ', 'voce errou a resposta correta é a teste1 , estude mais  vagabundo rsrsrs'),
(3, 'Correto! List comprehension é uma sintaxe elegante para criar listas em Python.', 'Incorreto. List comprehension é uma forma concisa de criar novas listas baseadas em sequências ou iteráveis existentes.'),
(4, 'Correto! __str__ é para representação legível por humanos, enquanto __repr__ é para representação não ambígua que poderia recriar o objeto.', 'Incorreto. __str__ e __repr__ têm propósitos diferentes: __str__ para leitura humana e __repr__ para representação precisa do objeto.'),
(5, 'Correto! O comando SELECT é usado para consultar dados em uma tabela SQL.', 'Incorreto. O comando SELECT é o comando básico para consultar dados em SQL.'),
(6, 'Correto! INNER JOIN mostra apenas registros com correspondência em ambas as tabelas, enquanto LEFT JOIN mantém todos os registros da tabela à esquerda.', 'Incorreto. INNER JOIN e LEFT JOIN têm comportamentos diferentes na combinação de registros.'),
(7, 'Correto! Uma subconsulta correlacionada é aquela que referencia colunas da consulta externa, sendo executada uma vez para cada linha da consulta principal.', 'Incorreto. Uma subconsulta correlacionada é uma subconsulta que depende da consulta externa, referenciando suas colunas.'),
(10, 'Correto! HTTP (Hypertext Transfer Protocol) é o protocolo padrão para transferência de páginas web.', 'Incorreto. HTTP é o protocolo usado para transferência de páginas web.'),
(11, 'Correto! O endereço MAC é um identificador único atribuído a interfaces de rede no momento da fabricação.', 'Incorreto. O endereço MAC é um identificador único de hardware usado para identificar dispositivos em uma rede.'),
(12, 'Correto! BGP é o protocolo que permite o roteamento entre diferentes sistemas autônomos na Internet.', 'Incorreto. BGP é o protocolo principal de roteamento entre sistemas autônomos na Internet.'),
(13, 'Correto! Docker é uma plataforma de containerização que permite empacotar e distribuir aplicações de forma isolada.', 'Incorreto. Docker é uma plataforma de containerização, não um sistema operacional ou linguagem de programação.'),
(14, 'Correto! CI é uma prática de desenvolvimento que visa integrar código frequentemente, detectando problemas mais cedo.', 'Incorreto. Integração Contínua é uma prática de desenvolvimento que envolve integração frequente de código com testes automatizados.');

-- --------------------------------------------------------

--
-- Estrutura para tabela `question_types`
--

CREATE TABLE `question_types` (
  `type_id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `question_types`
--

INSERT INTO `question_types` (`type_id`, `name`, `description`) VALUES
(1, 'Múltipla Escolha', 'Pergunta com alternativas A, B, C, D'),
(2, 'Resposta Escrita', 'Pergunta que requer uma resposta textual');

-- --------------------------------------------------------

--
-- Estrutura para tabela `quiz_sessions`
--

CREATE TABLE `quiz_sessions` (
  `session_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `category_id` int(11) NOT NULL,
  `difficulty_id` int(11) NOT NULL,
  `start_time` timestamp NOT NULL DEFAULT current_timestamp(),
  `end_time` timestamp NULL DEFAULT NULL,
  `total_points` int(11) DEFAULT 0,
  `accuracy_percentage` decimal(5,2) DEFAULT 0.00,
  `completed` tinyint(1) DEFAULT 0,
  `current_question_start` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `quiz_sessions`
--

INSERT INTO `quiz_sessions` (`session_id`, `user_id`, `category_id`, `difficulty_id`, `start_time`, `end_time`, `total_points`, `accuracy_percentage`, `completed`, `current_question_start`) VALUES
(1, 1, 1, 1, '2025-04-22 16:02:49', NULL, 93, 0.00, 0, NULL),
(2, 1, 2, 1, '2025-04-22 16:36:28', NULL, 31, 0.00, 0, NULL),
(3, 1, 2, 2, '2025-04-22 16:36:50', NULL, 0, 0.00, 0, NULL),
(4, 1, 2, 3, '2025-04-22 16:53:03', NULL, 0, 0.00, 0, NULL),
(5, 1, 3, 1, '2025-04-22 17:05:40', NULL, 0, 0.00, 0, NULL),
(6, 1, 4, 1, '2025-04-22 17:05:45', NULL, 30, 0.00, 0, NULL),
(7, 4, 1, 3, '2025-04-22 17:06:29', NULL, 378, 0.00, 0, NULL),
(8, 4, 3, 1, '2025-04-22 17:07:38', NULL, 0, 0.00, 0, NULL),
(9, 4, 3, 2, '2025-04-22 17:07:50', NULL, 72, 0.00, 0, NULL),
(10, 4, 3, 3, '2025-04-22 17:08:11', NULL, 0, 0.00, 0, NULL),
(11, 3, 1, 1, '2025-04-22 17:10:10', NULL, 125, 0.00, 0, NULL),
(12, 3, 4, 1, '2025-04-22 17:11:28', NULL, 10, 0.00, 0, NULL),
(13, 1, 1, 2, '2025-04-22 17:17:41', NULL, 216, 0.00, 0, NULL),
(14, 1, 3, 3, '2025-04-22 17:18:36', NULL, 378, 0.00, 0, NULL),
(15, 1, 5, 1, '2025-04-22 18:07:15', NULL, 0, 0.00, 0, NULL);

--
-- Acionadores `quiz_sessions`
--
DELIMITER $$
CREATE TRIGGER `complete_quiz_session` BEFORE UPDATE ON `quiz_sessions` FOR EACH ROW BEGIN
    IF NEW.completed = TRUE AND OLD.completed = FALSE THEN
        SET NEW.end_time = CURRENT_TIMESTAMP;
        
        -- Calcular precisão
        SET NEW.accuracy_percentage = (
            SELECT (SUM(is_correct) / COUNT(*)) * 100 
            FROM user_answers 
            WHERE session_id = NEW.session_id
        );
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estrutura para tabela `system_settings`
--

CREATE TABLE `system_settings` (
  `setting_id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `system_settings`
--

INSERT INTO `system_settings` (`setting_id`, `setting_key`, `setting_value`, `description`, `updated_at`) VALUES
(1, 'questions_per_quiz', '10', 'Número padrão de perguntas por quiz', '2025-04-22 14:58:01'),
(2, 'enable_timer', 'true', 'Habilitar temporizador para respostas', '2025-04-22 14:58:01'),
(3, 'consecutive_bonus_threshold', '3', 'Número de acertos consecutivos para bônus', '2025-04-22 14:58:01'),
(4, 'consecutive_bonus_percentage', '10', 'Porcentagem de bônus por acertos consecutivos', '2025-04-22 14:58:01'),
(5, 'time_bonus_percentage', '20', 'Porcentagem de bônus por resposta rápida', '2025-04-22 14:58:01'),
(6, 'time_bonus_threshold', '50', 'Porcentagem do tempo limite para ganhar bônus de tempo', '2025-04-22 14:58:01'),
(7, 'partial_match_enabled', 'true', 'Permitir correspondência parcial para respostas escritas', '2025-04-22 14:58:01'),
(8, 'ranking_limit', '10', 'Limite de usuários exibidos no ranking', '2025-04-22 14:58:01'),
(9, 'maintenance_mode', 'false', 'Sistema em manutenção', '2025-04-22 14:58:01');

-- --------------------------------------------------------

--
-- Estrutura para tabela `users`
--

CREATE TABLE `users` (
  `user_id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `is_admin` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_login` timestamp NULL DEFAULT NULL,
  `reset_token` varchar(255) DEFAULT NULL,
  `reset_token_expires` timestamp NULL DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `total_points` int(11) DEFAULT 0,
  `current_level` int(11) DEFAULT 1,
  `consecutive_correct_answers` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `users`
--

INSERT INTO `users` (`user_id`, `name`, `email`, `password_hash`, `is_admin`, `created_at`, `last_login`, `reset_token`, `reset_token_expires`, `is_active`, `total_points`, `current_level`, `consecutive_correct_answers`) VALUES
(1, 'Horst Fernandes Seifert', 'horst@gmail.com', '$2b$12$Tl8JSEWJGSW6dCQhwO.zx.fitDuvAbHfvyN6Fb6UQcgWnimHjslWO', 0, '2025-04-22 14:59:13', NULL, NULL, NULL, 1, 748, 3, 5),
(2, 'Administrador', 'admin@quizti.com', '$2b$12$/eYGP/GSCQqM2CqApZhHGOkz4o1V7X45AzHieNDAZrGtkL5ocFNJC', 1, '2025-04-22 15:35:46', NULL, NULL, NULL, 1, 0, 1, 0),
(3, '  ', 'teste@teste.com', '$2b$12$bHr6O2UuAmhE5geI8bMUPOzc6gAwvJjiClk3szAi0zPtYGUQyT.Ze', 0, '2025-04-22 17:03:17', NULL, NULL, NULL, 1, 135, 2, 2),
(4, 'pedro', 'inteiro@outdoor.com', '$2b$12$wdt.zjmrOQS03gxrtXkHr.yw1NW6zq5JIOAMJjIvZvDDoFN1g2Jqy', 0, '2025-04-22 17:06:01', NULL, NULL, NULL, 1, 450, 2, 8),
(5, 'a', 'a@aasdas.com', '$2b$12$pahT34zIiSpWXXV8GLy4JudEz9LoAlA5CbFi5xyu6wvxeH/1Jh.1i', 0, '2025-04-22 17:11:34', NULL, NULL, NULL, 1, 0, 1, 0);

--
-- Acionadores `users`
--
DELIMITER $$
CREATE TRIGGER `log_user_registration` AFTER INSERT ON `users` FOR EACH ROW BEGIN
    INSERT INTO activity_logs (user_id, action_type, action_description)
    VALUES (NEW.user_id, 'USER_REGISTER', CONCAT('Novo usuário registrado: ', NEW.name));
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_user_level` BEFORE UPDATE ON `users` FOR EACH ROW BEGIN
    DECLARE new_level INT;
    
    SELECT level_id INTO new_level FROM levels 
    WHERE NEW.total_points BETWEEN min_points AND max_points 
    LIMIT 1;
    
    IF new_level IS NOT NULL THEN
        SET NEW.current_level = new_level;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estrutura para tabela `user_answers`
--

CREATE TABLE `user_answers` (
  `answer_id` int(11) NOT NULL,
  `session_id` int(11) NOT NULL,
  `question_id` int(11) NOT NULL,
  `alternative_id` int(11) DEFAULT NULL,
  `written_response` text DEFAULT NULL,
  `is_correct` tinyint(1) DEFAULT 0,
  `points_earned` int(11) DEFAULT 0,
  `response_time` int(11) DEFAULT NULL,
  `time_limit_exceeded` tinyint(1) DEFAULT 0,
  `answered_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `user_answers`
--

INSERT INTO `user_answers` (`answer_id`, `session_id`, `question_id`, `alternative_id`, `written_response`, `is_correct`, `points_earned`, `response_time`, `time_limit_exceeded`, `answered_at`) VALUES
(1, 1, 1, 1, NULL, 1, 10, 10, 0, '2025-04-22 16:03:00'),
(2, 1, 1, 1, NULL, 1, 10, 36, 0, '2025-04-22 16:10:56'),
(3, 2, 5, 17, NULL, 1, 10, 8, 0, '2025-04-22 16:36:36'),
(4, 4, 7, 27, NULL, 0, 0, 21, 0, '2025-04-22 16:53:25'),
(5, 4, 7, 26, NULL, 0, 0, 4, 0, '2025-04-22 16:53:31'),
(6, 6, 13, 49, NULL, 1, 10, 9, 0, '2025-04-22 17:05:55'),
(7, 6, 13, 49, NULL, 1, 10, 4, 0, '2025-04-22 17:06:01'),
(8, 6, 13, 49, NULL, 1, 10, 0, 0, '2025-04-22 17:06:04'),
(9, 2, 5, 17, NULL, 1, 11, 4, 0, '2025-04-22 17:06:20'),
(10, 7, 4, 13, NULL, 1, 60, 10, 0, '2025-04-22 17:06:40'),
(11, 7, 4, 13, NULL, 1, 60, 10, 0, '2025-04-22 17:06:52'),
(12, 7, 4, 13, NULL, 1, 60, 10, 0, '2025-04-22 17:07:04'),
(13, 7, 4, 13, NULL, 1, 66, 5, 0, '2025-04-22 17:07:13'),
(14, 7, 4, 13, NULL, 1, 66, 3, 0, '2025-04-22 17:07:18'),
(15, 7, 4, 13, NULL, 1, 66, 6, 0, '2025-04-22 17:07:26'),
(16, 9, 11, 41, NULL, 1, 36, 9, 0, '2025-04-22 17:08:00'),
(17, 9, 11, 41, NULL, 1, 36, 4, 0, '2025-04-22 17:08:05'),
(18, 11, 2, 5, NULL, 1, 10, 7, 0, '2025-04-22 17:10:18'),
(19, 11, 1, 1, NULL, 1, 10, 9, 0, '2025-04-22 17:10:30'),
(20, 11, 1, 3, NULL, 0, 0, 3, 0, '2025-04-22 17:10:35'),
(21, 11, 2, 5, NULL, 1, 10, 5, 0, '2025-04-22 17:10:45'),
(22, 11, 2, 5, NULL, 1, 10, 10, 0, '2025-04-22 17:10:57'),
(23, 12, 13, 52, NULL, 0, 0, 7, 0, '2025-04-22 17:11:37'),
(24, 12, 13, 49, NULL, 1, 10, 4, 0, '2025-04-22 17:11:48'),
(25, 11, 1, 1, NULL, 1, 10, 4, 0, '2025-04-22 17:13:42'),
(26, 11, 1, 1, NULL, 1, 10, 2, 0, '2025-04-22 17:13:47'),
(27, 11, 1, 1, NULL, 1, 11, 1, 0, '2025-04-22 17:13:49'),
(28, 11, 1, 1, NULL, 1, 11, 1, 0, '2025-04-22 17:13:51'),
(29, 11, 2, 5, NULL, 1, 11, 3, 0, '2025-04-22 17:13:56'),
(30, 13, 3, 9, NULL, 1, 33, 14, 0, '2025-04-22 17:17:56'),
(31, 13, 3, 10, NULL, 0, 0, 6, 0, '2025-04-22 17:18:07'),
(32, 13, 3, 9, NULL, 1, 30, 1, 0, '2025-04-22 17:18:10'),
(33, 13, 3, 9, NULL, 1, 30, 2, 0, '2025-04-22 17:18:14'),
(34, 13, 3, 9, NULL, 1, 30, 2, 0, '2025-04-22 17:18:18'),
(35, 13, 3, 9, NULL, 1, 33, 3, 0, '2025-04-22 17:18:22'),
(36, 14, 12, 46, NULL, 0, 0, 5, 0, '2025-04-22 17:18:42'),
(37, 14, 12, 48, NULL, 0, 0, 1, 0, '2025-04-22 17:18:44'),
(38, 14, 12, 45, NULL, 1, 60, 3, 0, '2025-04-22 17:18:49'),
(39, 14, 12, 45, NULL, 1, 60, 1, 0, '2025-04-22 17:18:52'),
(40, 14, 12, 45, NULL, 1, 60, 1, 0, '2025-04-22 17:18:54'),
(41, 14, 12, 45, NULL, 1, 66, 1, 0, '2025-04-22 17:18:57'),
(42, 14, 12, 45, NULL, 1, 66, 1, 0, '2025-04-22 17:19:00'),
(43, 14, 12, 45, NULL, 1, 66, 1, 0, '2025-04-22 17:19:03'),
(44, 11, 1, 1, NULL, 1, 12, 577, 0, '2025-04-22 17:23:35'),
(45, 11, 1, 3, NULL, 0, 0, 55, 0, '2025-04-22 17:24:34'),
(46, 11, 1, 1, NULL, 1, 10, 17, 0, '2025-04-22 17:24:55'),
(47, 11, 1, 1, NULL, 1, 10, 20, 0, '2025-04-22 17:25:18'),
(48, 1, 2, 8, NULL, 0, 0, 131, 0, '2025-04-22 17:44:23'),
(49, 1, 2, 6, NULL, 0, 0, 2, 0, '2025-04-22 17:44:30'),
(50, 1, 1, 4, NULL, 0, 0, 3, 0, '2025-04-22 17:44:36'),
(51, 1, 2, 7, NULL, 0, 0, 2, 0, '2025-04-22 17:44:42'),
(52, 1, 2, 5, NULL, 1, 10, 1, 0, '2025-04-22 17:44:46'),
(53, 1, 2, 7, NULL, 0, 0, 2, 0, '2025-04-22 17:44:58'),
(54, 2, 5, 19, NULL, 0, 0, 6, 0, '2025-04-22 17:50:16'),
(55, 2, 5, 17, NULL, 1, 10, 9, 0, '2025-04-22 17:50:28'),
(56, 13, 3, 9, NULL, 1, 30, 6, 0, '2025-04-22 17:50:47'),
(57, 13, 3, 9, NULL, 1, 30, 7, 0, '2025-04-22 17:50:56'),
(58, 1, 2, 5, NULL, 1, 11, 2, 0, '2025-04-22 17:51:04'),
(59, 1, 2, 8, NULL, 0, 0, 72, 0, '2025-04-22 17:52:19'),
(60, 1, 2, 5, NULL, 1, 10, 2, 0, '2025-04-22 17:52:23'),
(61, 1, 2, 5, NULL, 1, 10, 3, 0, '2025-04-22 17:54:06'),
(62, 1, 2, 5, NULL, 1, 10, 3, 0, '2025-04-22 17:54:11'),
(63, 1, 2, 5, NULL, 1, 11, 6, 0, '2025-04-22 17:54:25'),
(64, 1, 1, 1, NULL, 1, 11, 5, 0, '2025-04-22 17:54:32');

--
-- Acionadores `user_answers`
--
DELIMITER $$
CREATE TRIGGER `block_question_on_timeout` AFTER INSERT ON `user_answers` FOR EACH ROW BEGIN
    DECLARE question_time_limit INT;
    DECLARE session_user_id INT;
    
    IF NEW.time_limit_exceeded = TRUE THEN
        -- Obtém o usuário da sessão
        SELECT user_id INTO session_user_id
        FROM quiz_sessions
        WHERE session_id = NEW.session_id;
        
        -- Obtém o tempo limite da questão
        SELECT d.time_limit INTO question_time_limit
        FROM questions q
        JOIN difficulties d ON q.difficulty_id = d.difficulty_id
        WHERE q.question_id = NEW.question_id;
        
        -- Insere ou atualiza o bloqueio
        INSERT INTO user_question_blocks (user_id, question_id, blocked_until)
        VALUES (
            session_user_id, 
            NEW.question_id, 
            DATE_ADD(NOW(), INTERVAL 24 HOUR)
        )
        ON DUPLICATE KEY UPDATE
            blocked_until = DATE_ADD(NOW(), INTERVAL 24 HOUR);
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `calculate_points_on_answer` BEFORE INSERT ON `user_answers` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `check_time_limit_before_answer` BEFORE INSERT ON `user_answers` FOR EACH ROW BEGIN
    DECLARE question_time_limit INT;
    DECLARE session_user_id INT;
    DECLARE last_answer_time TIMESTAMP;
    
    -- Obter informações da sessão e tempo limite
    SELECT qs.user_id, d.time_limit 
    INTO session_user_id, question_time_limit
    FROM quiz_sessions qs
    JOIN questions q ON NEW.question_id = q.question_id
    JOIN difficulties d ON q.difficulty_id = d.difficulty_id
    WHERE qs.session_id = NEW.session_id;
    
    -- Obter o tempo da última resposta para esta sessão
    SELECT MAX(answered_at) 
    INTO last_answer_time
    FROM user_answers
    WHERE session_id = NEW.session_id;
    
    -- Se não houver resposta anterior, usar o tempo de início da sessão
    IF last_answer_time IS NULL THEN
        SELECT start_time INTO last_answer_time
        FROM quiz_sessions
        WHERE session_id = NEW.session_id;
    END IF;
    
    -- Verificar se o usuário já respondeu esta questão
    IF EXISTS (
        SELECT 1 
        FROM user_answers ua
        JOIN quiz_sessions qs ON ua.session_id = qs.session_id
        WHERE qs.user_id = session_user_id
        AND ua.question_id = NEW.question_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Esta questão já foi respondida anteriormente';
    END IF;
    
    -- Se excedeu o tempo limite (tempo_limite em segundos)
    IF TIMESTAMPDIFF(SECOND, last_answer_time, NOW()) > question_time_limit THEN
        -- Marcar como tempo excedido
        SET NEW.time_limit_exceeded = TRUE;
        SET NEW.is_correct = FALSE;
        SET NEW.points_earned = 0;
        
        -- Inserir bloqueio da questão
        INSERT INTO user_question_blocks (user_id, question_id, blocked_until)
        VALUES (
            session_user_id, 
            NEW.question_id, 
            DATE_ADD(NOW(), INTERVAL 24 HOUR)
        )
        ON DUPLICATE KEY UPDATE
            blocked_until = DATE_ADD(NOW(), INTERVAL 24 HOUR);
            
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Tempo limite excedido para esta questão';
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `update_user_points_after_answer` AFTER INSERT ON `user_answers` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estrutura para tabela `user_badges`
--

CREATE TABLE `user_badges` (
  `user_id` int(11) NOT NULL,
  `badge_id` int(11) NOT NULL,
  `earned_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `user_badges`
--

INSERT INTO `user_badges` (`user_id`, `badge_id`, `earned_at`) VALUES
(1, 20, '2025-04-22 17:18:14'),
(1, 23, '2025-04-22 17:18:52'),
(3, 20, '2025-04-22 17:23:35'),
(4, 20, '2025-04-22 17:06:52');

-- --------------------------------------------------------

--
-- Estrutura para tabela `user_categories`
--

CREATE TABLE `user_categories` (
  `user_id` int(11) NOT NULL,
  `category_id` int(11) NOT NULL,
  `points` int(11) DEFAULT 0,
  `questions_answered` int(11) DEFAULT 0,
  `correct_answers` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Despejando dados para a tabela `user_categories`
--

INSERT INTO `user_categories` (`user_id`, `category_id`, `points`, `questions_answered`, `correct_answers`) VALUES
(1, 1, 309, 23, 16),
(1, 2, 31, 6, 3),
(1, 3, 378, 8, 6),
(1, 4, 30, 3, 3),
(3, 1, 125, 14, 12),
(3, 4, 10, 2, 1),
(4, 1, 378, 6, 6),
(4, 3, 72, 2, 2);

-- --------------------------------------------------------

--
-- Estrutura stand-in para view `user_performance`
-- (Veja abaixo para a visão atual)
--
CREATE TABLE `user_performance` (
`user_id` int(11)
,`name` varchar(100)
,`total_points` int(11)
,`level_name` varchar(50)
,`quizzes_completed` bigint(21)
,`total_questions_answered` bigint(21)
,`correct_answers` decimal(22,0)
,`overall_accuracy` decimal(28,2)
,`badges_earned` bigint(21)
);

-- --------------------------------------------------------

--
-- Estrutura para tabela `user_question_blocks`
--

CREATE TABLE `user_question_blocks` (
  `user_id` int(11) NOT NULL,
  `question_id` int(11) NOT NULL,
  `blocked_until` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estrutura stand-in para view `user_question_status`
-- (Veja abaixo para a visão atual)
--
CREATE TABLE `user_question_status` (
`question_id` int(11)
,`user_id` int(11)
,`has_correct_answer` tinyint(1)
,`attempt_count` bigint(21)
,`last_attempt` timestamp
);

-- --------------------------------------------------------

--
-- Estrutura para tabela `written_answers`
--

CREATE TABLE `written_answers` (
  `answer_id` int(11) NOT NULL,
  `question_id` int(11) NOT NULL,
  `correct_answer` text NOT NULL,
  `alternative_answers` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estrutura para view `category_performance`
--
DROP TABLE IF EXISTS `category_performance`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `category_performance`  AS SELECT `c`.`category_id` AS `category_id`, `c`.`name` AS `category`, count(distinct `ua`.`session_id`) AS `total_sessions`, count(`ua`.`answer_id`) AS `total_questions`, sum(if(`ua`.`is_correct` = 1,1,0)) AS `correct_answers`, round(sum(if(`ua`.`is_correct` = 1,1,0)) / count(`ua`.`answer_id`) * 100,2) AS `accuracy`, avg(`ua`.`points_earned`) AS `avg_points_per_question` FROM ((`categories` `c` join `questions` `q` on(`c`.`category_id` = `q`.`category_id`)) join `user_answers` `ua` on(`q`.`question_id` = `ua`.`question_id`)) GROUP BY `c`.`category_id` ORDER BY round(sum(if(`ua`.`is_correct` = 1,1,0)) / count(`ua`.`answer_id`) * 100,2) DESC ;

-- --------------------------------------------------------

--
-- Estrutura para view `global_ranking`
--
DROP TABLE IF EXISTS `global_ranking`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `global_ranking`  AS SELECT `u`.`user_id` AS `user_id`, `u`.`name` AS `name`, `u`.`total_points` AS `total_points`, `u`.`current_level` AS `current_level`, `l`.`level_name` AS `level_name`, (select count(0) from `user_badges` `ub` where `ub`.`user_id` = `u`.`user_id`) AS `badges_count` FROM (`users` `u` join `levels` `l` on(`u`.`current_level` = `l`.`level_id`)) WHERE `u`.`is_active` = 1 ORDER BY `u`.`total_points` DESC ;

-- --------------------------------------------------------

--
-- Estrutura para view `most_failed_questions`
--
DROP TABLE IF EXISTS `most_failed_questions`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `most_failed_questions`  AS SELECT `q`.`question_id` AS `question_id`, `q`.`content` AS `content`, count(`ua`.`answer_id`) AS `total_attempts`, sum(if(`ua`.`is_correct` = 0,1,0)) AS `incorrect_attempts`, round(sum(if(`ua`.`is_correct` = 0,1,0)) / count(`ua`.`answer_id`) * 100,2) AS `failure_rate`, `c`.`name` AS `category`, `d`.`name` AS `difficulty` FROM (((`questions` `q` join `user_answers` `ua` on(`q`.`question_id` = `ua`.`question_id`)) join `categories` `c` on(`q`.`category_id` = `c`.`category_id`)) join `difficulties` `d` on(`q`.`difficulty_id` = `d`.`difficulty_id`)) GROUP BY `q`.`question_id` HAVING `total_attempts` >= 5 ORDER BY round(sum(if(`ua`.`is_correct` = 0,1,0)) / count(`ua`.`answer_id`) * 100,2) DESC ;

-- --------------------------------------------------------

--
-- Estrutura para view `user_performance`
--
DROP TABLE IF EXISTS `user_performance`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `user_performance`  AS SELECT `u`.`user_id` AS `user_id`, `u`.`name` AS `name`, `u`.`total_points` AS `total_points`, `l`.`level_name` AS `level_name`, count(distinct `qs`.`session_id`) AS `quizzes_completed`, count(`ua`.`answer_id`) AS `total_questions_answered`, sum(if(`ua`.`is_correct` = 1,1,0)) AS `correct_answers`, round(sum(if(`ua`.`is_correct` = 1,1,0)) / count(`ua`.`answer_id`) * 100,2) AS `overall_accuracy`, (select count(0) from `user_badges` `ub` where `ub`.`user_id` = `u`.`user_id`) AS `badges_earned` FROM (((`users` `u` left join `levels` `l` on(`u`.`current_level` = `l`.`level_id`)) left join `quiz_sessions` `qs` on(`u`.`user_id` = `qs`.`user_id` and `qs`.`completed` = 1)) left join `user_answers` `ua` on(`qs`.`session_id` = `ua`.`session_id`)) WHERE `u`.`is_active` = 1 GROUP BY `u`.`user_id` ORDER BY `u`.`total_points` DESC ;

-- --------------------------------------------------------

--
-- Estrutura para view `user_question_status`
--
DROP TABLE IF EXISTS `user_question_status`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `user_question_status`  AS SELECT `ua`.`question_id` AS `question_id`, `qs`.`user_id` AS `user_id`, max(`ua`.`is_correct`) AS `has_correct_answer`, count(0) AS `attempt_count`, max(`ua`.`answered_at`) AS `last_attempt` FROM (`user_answers` `ua` join `quiz_sessions` `qs` on(`ua`.`session_id` = `qs`.`session_id`)) GROUP BY `ua`.`question_id`, `qs`.`user_id` ;

--
-- Índices para tabelas despejadas
--

--
-- Índices de tabela `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD PRIMARY KEY (`log_id`),
  ADD KEY `idx_user_action` (`user_id`,`action_type`),
  ADD KEY `idx_created_at` (`created_at`);

--
-- Índices de tabela `alternatives`
--
ALTER TABLE `alternatives`
  ADD PRIMARY KEY (`alternative_id`),
  ADD KEY `idx_question` (`question_id`);

--
-- Índices de tabela `badges`
--
ALTER TABLE `badges`
  ADD PRIMARY KEY (`badge_id`),
  ADD UNIQUE KEY `name` (`name`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `idx_badges_condition` (`achievement_condition`,`achievement_threshold`);

--
-- Índices de tabela `categories`
--
ALTER TABLE `categories`
  ADD PRIMARY KEY (`category_id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Índices de tabela `difficulties`
--
ALTER TABLE `difficulties`
  ADD PRIMARY KEY (`difficulty_id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Índices de tabela `levels`
--
ALTER TABLE `levels`
  ADD PRIMARY KEY (`level_id`),
  ADD UNIQUE KEY `unique_level_range` (`min_points`,`max_points`);

--
-- Índices de tabela `questions`
--
ALTER TABLE `questions`
  ADD PRIMARY KEY (`question_id`),
  ADD KEY `difficulty_id` (`difficulty_id`),
  ADD KEY `type_id` (`type_id`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `idx_category_difficulty` (`category_id`,`difficulty_id`),
  ADD KEY `idx_questions_category_difficulty` (`category_id`,`difficulty_id`,`is_active`);

--
-- Índices de tabela `question_feedback`
--
ALTER TABLE `question_feedback`
  ADD PRIMARY KEY (`question_id`);

--
-- Índices de tabela `question_types`
--
ALTER TABLE `question_types`
  ADD PRIMARY KEY (`type_id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Índices de tabela `quiz_sessions`
--
ALTER TABLE `quiz_sessions`
  ADD PRIMARY KEY (`session_id`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `difficulty_id` (`difficulty_id`),
  ADD KEY `idx_user_completed` (`user_id`,`completed`),
  ADD KEY `idx_quiz_sessions_user` (`user_id`,`completed`);

--
-- Índices de tabela `system_settings`
--
ALTER TABLE `system_settings`
  ADD PRIMARY KEY (`setting_id`),
  ADD UNIQUE KEY `setting_key` (`setting_key`);

--
-- Índices de tabela `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`user_id`),
  ADD UNIQUE KEY `email` (`email`),
  ADD KEY `idx_email` (`email`),
  ADD KEY `idx_points` (`total_points`);

--
-- Índices de tabela `user_answers`
--
ALTER TABLE `user_answers`
  ADD PRIMARY KEY (`answer_id`),
  ADD KEY `alternative_id` (`alternative_id`),
  ADD KEY `idx_session` (`session_id`),
  ADD KEY `idx_question` (`question_id`),
  ADD KEY `idx_user_answers_correctness` (`is_correct`);

--
-- Índices de tabela `user_badges`
--
ALTER TABLE `user_badges`
  ADD PRIMARY KEY (`user_id`,`badge_id`),
  ADD KEY `badge_id` (`badge_id`);

--
-- Índices de tabela `user_categories`
--
ALTER TABLE `user_categories`
  ADD PRIMARY KEY (`user_id`,`category_id`),
  ADD KEY `idx_category_points` (`category_id`,`points`);

--
-- Índices de tabela `user_question_blocks`
--
ALTER TABLE `user_question_blocks`
  ADD PRIMARY KEY (`user_id`,`question_id`),
  ADD KEY `question_id` (`question_id`),
  ADD KEY `idx_user_question_blocks_time` (`blocked_until`);

--
-- Índices de tabela `written_answers`
--
ALTER TABLE `written_answers`
  ADD PRIMARY KEY (`answer_id`),
  ADD UNIQUE KEY `question_id` (`question_id`);

--
-- AUTO_INCREMENT para tabelas despejadas
--

--
-- AUTO_INCREMENT de tabela `activity_logs`
--
ALTER TABLE `activity_logs`
  MODIFY `log_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de tabela `alternatives`
--
ALTER TABLE `alternatives`
  MODIFY `alternative_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=61;

--
-- AUTO_INCREMENT de tabela `badges`
--
ALTER TABLE `badges`
  MODIFY `badge_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=35;

--
-- AUTO_INCREMENT de tabela `categories`
--
ALTER TABLE `categories`
  MODIFY `category_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT de tabela `difficulties`
--
ALTER TABLE `difficulties`
  MODIFY `difficulty_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de tabela `levels`
--
ALTER TABLE `levels`
  MODIFY `level_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de tabela `questions`
--
ALTER TABLE `questions`
  MODIFY `question_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT de tabela `question_types`
--
ALTER TABLE `question_types`
  MODIFY `type_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de tabela `quiz_sessions`
--
ALTER TABLE `quiz_sessions`
  MODIFY `session_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT de tabela `system_settings`
--
ALTER TABLE `system_settings`
  MODIFY `setting_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT de tabela `users`
--
ALTER TABLE `users`
  MODIFY `user_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de tabela `user_answers`
--
ALTER TABLE `user_answers`
  MODIFY `answer_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=65;

--
-- AUTO_INCREMENT de tabela `written_answers`
--
ALTER TABLE `written_answers`
  MODIFY `answer_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- Restrições para tabelas despejadas
--

--
-- Restrições para tabelas `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD CONSTRAINT `activity_logs_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`);

--
-- Restrições para tabelas `alternatives`
--
ALTER TABLE `alternatives`
  ADD CONSTRAINT `alternatives_ibfk_1` FOREIGN KEY (`question_id`) REFERENCES `questions` (`question_id`) ON DELETE CASCADE;

--
-- Restrições para tabelas `badges`
--
ALTER TABLE `badges`
  ADD CONSTRAINT `badges_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`);

--
-- Restrições para tabelas `questions`
--
ALTER TABLE `questions`
  ADD CONSTRAINT `questions_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`),
  ADD CONSTRAINT `questions_ibfk_2` FOREIGN KEY (`difficulty_id`) REFERENCES `difficulties` (`difficulty_id`),
  ADD CONSTRAINT `questions_ibfk_3` FOREIGN KEY (`type_id`) REFERENCES `question_types` (`type_id`),
  ADD CONSTRAINT `questions_ibfk_4` FOREIGN KEY (`created_by`) REFERENCES `users` (`user_id`);

--
-- Restrições para tabelas `question_feedback`
--
ALTER TABLE `question_feedback`
  ADD CONSTRAINT `question_feedback_ibfk_1` FOREIGN KEY (`question_id`) REFERENCES `questions` (`question_id`) ON DELETE CASCADE;

--
-- Restrições para tabelas `quiz_sessions`
--
ALTER TABLE `quiz_sessions`
  ADD CONSTRAINT `quiz_sessions_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`),
  ADD CONSTRAINT `quiz_sessions_ibfk_2` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`),
  ADD CONSTRAINT `quiz_sessions_ibfk_3` FOREIGN KEY (`difficulty_id`) REFERENCES `difficulties` (`difficulty_id`);

--
-- Restrições para tabelas `user_answers`
--
ALTER TABLE `user_answers`
  ADD CONSTRAINT `user_answers_ibfk_1` FOREIGN KEY (`session_id`) REFERENCES `quiz_sessions` (`session_id`),
  ADD CONSTRAINT `user_answers_ibfk_2` FOREIGN KEY (`question_id`) REFERENCES `questions` (`question_id`),
  ADD CONSTRAINT `user_answers_ibfk_3` FOREIGN KEY (`alternative_id`) REFERENCES `alternatives` (`alternative_id`);

--
-- Restrições para tabelas `user_badges`
--
ALTER TABLE `user_badges`
  ADD CONSTRAINT `user_badges_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`),
  ADD CONSTRAINT `user_badges_ibfk_2` FOREIGN KEY (`badge_id`) REFERENCES `badges` (`badge_id`);

--
-- Restrições para tabelas `user_categories`
--
ALTER TABLE `user_categories`
  ADD CONSTRAINT `user_categories_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`),
  ADD CONSTRAINT `user_categories_ibfk_2` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`);

--
-- Restrições para tabelas `user_question_blocks`
--
ALTER TABLE `user_question_blocks`
  ADD CONSTRAINT `user_question_blocks_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`),
  ADD CONSTRAINT `user_question_blocks_ibfk_2` FOREIGN KEY (`question_id`) REFERENCES `questions` (`question_id`);

--
-- Restrições para tabelas `written_answers`
--
ALTER TABLE `written_answers`
  ADD CONSTRAINT `written_answers_ibfk_1` FOREIGN KEY (`question_id`) REFERENCES `questions` (`question_id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

-- Criar tabela de feedback para perguntas
CREATE TABLE question_feedback (
    question_id INT NOT NULL PRIMARY KEY,
    correct_feedback TEXT NOT NULL,
    incorrect_feedback TEXT NOT NULL,
    FOREIGN KEY (question_id) REFERENCES questions(question_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Adicionar feedback padrão para perguntas existentes
INSERT INTO question_feedback (question_id, correct_feedback, incorrect_feedback)
SELECT 
    question_id,
    'Parabéns! Você acertou!',
    'Ops! Tente novamente.'
FROM questions; 
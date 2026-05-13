# BTS_SHOW_SQL
Otimização de consultas em larga escala (5M+ registros) utilizando Materialized Views e Índices B-Tree no PostgreSQL. Projeto desenvolvido para o curso de ADS (SENAC/Porto Digital).

# 🎫BTS Ingressos 
*Otimização de Performance* 

Este repositório contém o script SQL desenvolvido para otimizar um sistema de alta volumetria (5 milhões de registros), simulando um ambiente real de venda de ingressos.

## 🚀 Métricas de Performance (Benchmark)
A estratégia de otimização focou na redução de I/O e processamento de agregados:

- **Consultas em Tabelas Brutas (Seq Scan):** ~37.500 ms (37,5 segundos)
- **Consultas Otimizadas (Materialized Views + B-Tree):** **0.034 ms a 0.058 ms** ⚡

## 🛠️ Tecnologias e Estratégias
- **PostgreSQL 16 / pgAdmin 4**
- **Materialized Views:** Para pré-processamento de agregados (Faturamento e Disponibilidade).
- **Índices B-Tree:** Para aceleração de filtros e séries temporais.
- **Window Functions:** Para cálculos complexos de receita acumulada.
- **Apoio Técnico:** Engenharia de prompts com Gemini 3 Flash e Claude 3.5 Sonnet para validação de sintaxe e geração de massa de dados.

## 📂 Status do Repositório
- [x] Script SQL de Infraestrutura e Views.
- [ ] Documentação Técnica (.docx) e Prints de EXPLAIN ANALYZE (Em breve).

---
*Projeto desenvolvido para a disciplina de Banco de Dados - ADS (SENAC / Porto Digital)*

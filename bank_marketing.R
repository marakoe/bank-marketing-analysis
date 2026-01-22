# Analyse von Kundensegmenten

library(tidyverse)
library(caret)
library(rpart)
library(rpart.plot)
library(rsample)
library(ggrepel)

#setwd("C:\\Users\\marak\\OneDrive\\Desktop\\bank_marketing")
raw_data = read.csv(".\\data\\raw\\bank-full.csv", sep = ";")

data = raw_data |> 
  select(age, job, marital, education, default, balance, housing, loan, poutcome, previous, y) |> 
  mutate(y = as.factor(y),
         default = as.factor(default),
         loan = as.factor(loan),
         housing = as.factor(housing)) 
# poutcome behält die kategorie 'unknown' da sie eine substantielle Antwort darstellt (Kontakt hat nicht stattgefunden)

### EDA

summary(data)

# Diskrete Variablen auswählen
categorical_vars <- data  |> 
  select(where(is.factor), where(is.character))  |> 
  names()

# Numerische Variablen auswählen
numerical_vars  <- data |> 
  select(where(is.numeric)) |> 
  names() 

## Univariate Verteilung

data |> 
  select(all_of(categorical_vars)) |> 
  pivot_longer(everything(), names_to = "Variable", values_to = "Wert") |> 
  ggplot(aes(x = Wert)) +
  geom_bar(fill = "steelblue") +
  coord_flip() +
  facet_wrap(~ Variable, scales = "free_y", ncol = 2) +
  labs(title = "Verteilung aller diskreten Variablen",
       y = "Anzahl") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

data |> 
  select(all_of(numerical_vars)) |> 
  pivot_longer(everything(), names_to = "Variable", values_to = "Wert") |> 
  ggplot(aes(x = Wert)) +
  geom_histogram(fill = "steelblue", bins = 40) +
  facet_wrap(~ Variable, scales = "free", ncol = 2) +
  labs(title = "Verteilung aller numerischen Variablen",
       y = "Anzahl") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

## Vertragsabschlussquote nach Ausprägung

categorical_vars <- categorical_vars[categorical_vars != 'y']

data |> 
  pivot_longer(cols = all_of(categorical_vars),
               names_to = "Variable", 
               values_to = "Wert") |> 
  group_by(Variable, Wert) |> 
  summarise(
    n = n(),
    subscribed_count = sum(y == 'yes'),
    prop_subscribed = subscribed_count / n,
    .groups = "drop"
  ) |> 
  mutate(Variable = factor(Variable, levels = categorical_vars)) |> 
  ggplot(aes(x = Wert, y = prop_subscribed)) +
  geom_col(fill = "steelblue") +
  coord_flip() +                        
  facet_wrap(~ Variable, scales = "free_y", ncol = 2) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Erfolgsquote pro Kategorie",
       y = "Anteil subscribed (%)",
       x = NULL) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        strip.text = element_text(size = 10, face = "bold"))

data |> 
  pivot_longer(cols = all_of(numerical_vars), 
               names_to = "Variable", 
               values_to = "Wert") |> 
  group_by(Variable, Wert) |> 
  summarise(
    n = n(),
    subscribed_count = sum(y == 'yes'),
    prop_subscribed = subscribed_count / n,
    .groups = "drop"
  ) |> 
  mutate(Variable = factor(Variable, levels = numerical_vars)) |> 
  ggplot(aes(x = Wert, y = prop_subscribed)) +
  geom_point(color = "steelblue") +
  geom_smooth(se=FALSE, color = "red")+
  facet_wrap(~ Variable, scales = "free_x", ncol = 2) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Erfolgsquote",
       y = "Anteil subscribed (%)",
       x = NULL) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        strip.text = element_text(size = 10, face = "bold"))

# Erstellung kategorisierter Variablen auf Grund schiefer Verteilungen und Outlier
data <- data |> 
  mutate(age_cat = cut(age, c(0, 30, 40, 50, Inf), labels = c('<30', '31-40', '41-50', '50<')),
         balance_cat = cut(balance, c(-Inf, 0, 70, 450, 1400, Inf), labels = c('<0', '1-70', '71-450', '451-1400', '1401<')),
         previous_bin = if_else(previous == 0, 'no', 'yes'))
table(data$age_cat)
table(data$balance_cat)
table(data$previous_bin)

## Training des Decision Trees (Fünffache Wiederholung für stabilere Ergebnisse)

results = data.frame()
for (seed in 1:5) {
  set.seed(seed)
  split <- initial_split(data, prop = 0.7, strata = y)
  train <- training(split)
  test  <- testing(split)
for(cost in c(5, 10, 15, 20)){ 
  for(mb in c(200, 300, 500)){ 
    for(cp in c(0.001, 0.005, 0.01, 0.02)){
      tree_costsens <- rpart(y ~ age_cat + marital + education + 
                               default + job + balance_cat + housing + loan + 
                               poutcome + previous_bin,
                             data = train,
                             method = "class",
                             parms = list(split = "information",
                                          loss = matrix(c(0, cost, 1, 0), # Gewichtung auf Grund stark unausgeglichener y-Variable
                                                        nrow=2,
                                                        dimnames = list(c("no", "yes"), 
                                                                        c("no", "yes")))),
                             control = rpart.control(minbucket=mb,
                                                     cp=cp))
      predictions <- predict(tree_costsens, test, type = "class")
      confMatrix <- confusionMatrix(predictions, test$y, positive = 'yes')
      result <- data.frame(cost = cost,
                           mb = mb,
                           cp = cp,
                           pred_yes = sum(predictions=='yes') / length(predictions),
                           sensitivity = confMatrix$byClass['Sensitivity'],
                           seed = seed)
      results <- rbind(results, result)
    }
  }
}
}

results_agg <- results |>
    group_by(cost, mb, cp) |>
    summarise(
      mean_pred_yes   = mean(pred_yes),
      sd_pred_yes     = sd(pred_yes),
      mean_sensitivity = mean(sensitivity),
      sd_sensitivity   = sd(sensitivity),
      .groups = "drop"
    )

#Plot der durchschnittlichen Ergebnisse für jede Modellvariante

ggplot(results_agg, aes(x = mean_pred_yes, y = mean_sensitivity))+
  geom_point()+
  geom_text_repel(aes(label = rownames(results_agg)), size = 3, box.padding = 0.5, max.overlaps = 100)+
  geom_abline(intercept = 0, slope = 1, color = "red", size = 1)+
  xlim(0, 1.2) +
  ylim(0, 1.2) 



# Modellvariante 1 (Modell 21): 40.06% der Personen erwirken 66.05% der Vertragsabschlüsse
model1 <- rpart(y ~ age_cat + marital + education + 
                         default + job + balance_cat + housing + loan + 
                         poutcome + previous_bin,
                       data = train,
                       method = "class",
                       parms = list(split = "information",
                                    loss = matrix(c(0, 10, 1, 0), # Gewichtung auf Grund stark unausgeglichener y-Variable
                                                  nrow=2,
                                                  dimnames = list(c("no", "yes"), 
                                                                  c("no", "yes")))),
                       control = rpart.control(minbucket=500,
                                               cp=0.001))
rpart.plot(model1, type=4, extra=104, tweak = 1, box.palette="RdYlGn")
  
# Modellvariante 2 (Modell 11): 15.95% der Personen erwirken 41.2% der Vertragsabschlüsse
model2 <- rpart(y ~ age_cat + marital + education + 
                  default + job + balance_cat + housing + loan + 
                  poutcome + previous_bin,
                data = train,
                method = "class",
                parms = list(split = "information",
                             loss = matrix(c(0, 5, 1, 0), # Gewichtung auf Grund stark unausgeglichener y-Variable
                                           nrow=2,
                                           dimnames = list(c("no", "yes"), 
                                                           c("no", "yes")))),
                control = rpart.control(minbucket=500,
                                        cp=0.01))
rpart.plot(model2, type=4, extra=104, tweak=1, box.palette="RdYlGn")



library("readxl")
library(dplyr)
library("ggplot2")
library("ggpubr") 
library("plyr")
library(tidyr)
library(tidyverse)
library(openxlsx)

# load data
main = '/Users/cgomez11/Documents/PhD/2021-spring/HRI/project/data/'
surveyData = read_excel(paste(main,'survey/export.xlsx', sep=""))
# demo has demographic information
demographics = read_excel(paste(main,'demographic/export.xlsx', sep=""))
# conditions has user data
conditions = read_excel(paste(main,'user/export.xlsx', sep=""))
imageData = read_excel(paste(main,'image/export.xlsx', sep=""))
# Load all files found and merge them
path = paste(main,'guess/', sep="")
merge_file_name = paste(main,'guess/export.xlsx', sep="")

filenames_list <- list.files(path= path, full.names=TRUE)

All <- lapply(filenames_list,function(filename){
  print(paste("Merging",filename,sep = ""))
  read.xlsx(filename)
})

df <- do.call(rbind.data.frame, All)
write.xlsx(df,merge_file_name)
# load file with merged responses
responses = read_excel(paste(main,'guess/export.xlsx', sep=""))

# rename all columns with spaces
surveyData <- surveyData %>%  rename_with(~ gsub(' ', '_', .x))
demographics <- demographics %>%  rename_with(~ gsub(' ', '_', .x))
conditions <- conditions %>%  rename_with(~ gsub(' ', '_', .x))
responses <- responses %>%  rename_with(~ gsub('\\.', '_', .x))
imageData <- imageData %>%  rename_with(~ gsub(' ', '_', .x))

# only select the users that completed the final survey
valid_users = unique(surveyData$User_id)

# filter other information of valid users
demographics = demographics[is.element(demographics$User_id, valid_users),]
conditions = conditions[is.element(conditions$User_id, valid_users),]
responses = responses[is.element(responses$User_id, valid_users),]
# remove users with an initial guess of 0 
responses = subset(responses, responses$Init_guess>0)

# compute performance, variation wrt initial guess, variation wrt AI
# time to enter the final response

# compare with imageData to get performance: add Truth column
responses = dplyr::inner_join(responses, select(imageData, Q_id, Truth), by="Q_id")
# compare with conditions to get performance: add Timing column
responses = dplyr::inner_join(responses, select(conditions,User_id, Timing), by="User_id")
# adjust large values in Resp_time
responses$Resp_time[responses$Resp_time>100 & responses$Timing==12] = 12
responses$Resp_time[responses$Resp_time>100 & responses$Timing==6] = 6
# normalize Resp_Time wrt Timing
responses$Resp_time = responses$Resp_time / responses$Timing

# variables to compute the final outcome
Init_guess = responses$Init_guess
Final_guess = responses$Final_guess
Truth = responses$Truth
Ai_suggestion = responses$Ai_suggestion

out=dplyr::summarise(group_by(responses, User_id, Q_id, Resp_time), Change=abs(Final_guess-Init_guess)/(Init_guess), 
                                                                    Error=abs(Final_guess-Truth)/Truth,
                                                                    Bias=abs(Final_guess-Ai_suggestion)/Ai_suggestion)
# all the objective metrics
Change = out$Change
Error = out$Error
Bias = out$Bias
Resp_time = out$Resp_time 

# merge easy and hard instances: average for each
out$Q_id[grepl('E', out$Q_id)]='easy'
out$Q_id[grepl('H', out$Q_id)]='hard'

# replace in Outcome=mean(x) where x can be Change, Error, Bias, Resp_time
by_task=dplyr::summarise(group_by(out, User_id, Q_id), Outcome=mean(Resp_time))
easy = subset(by_task, by_task$Q_id=="easy")
hard = subset(by_task, by_task$Q_id=="hard")

# create new data frame with all user information
conditions_info = conditions[c("User_id","Timing")]
conditions_info$Timing[conditions_info$Timing==6]='short'
conditions_info$Timing[conditions_info$Timing==12]='long'
user_info = dplyr::inner_join(conditions_info, demographics, by="User_id")

task_info <- data.frame('User_id'=easy$User_id,
                        'easy'=easy$Outcome, 
                        'hard'=hard$Outcome)
# merge user info with task info
# add as new columns to df, then gather into task column
df_responses = dplyr::inner_join(user_info, task_info, by="User_id")
# get demographic summaries of valid users: Age, Gender, Rate, Education, Timing
demo_count = dplyr::count(df_responses, Timing) 
demo_count$n = demo_count$n/sum(demo_count$n)
demo_count

df_responses = gather(df_responses, key="Task", value="Outcome", c("easy", "hard"))
df_responses$Task = factor(df_responses$Task)
df_responses$Timing = factor(df_responses$Timing)
df_responses$User_id = factor(df_responses$User_id)
df_responses$Age = factor(df_responses$Age)

# Average change in final response wrt initial guess
# Average counting error wrt groundtruth
# Average time to update response wrt timing condition
# Average difference between final response and AI suggestion wrt AI
ggplot(df_responses, aes(x=Timing, y=Outcome, fill=Task)) + 
  geom_boxplot() + ggtitle("Average difference between final response and AI") +
  ylab("Difference with AI")

# get statistics
df_responses %>% 
  group_by(Timing, Task) %>%
  get_summary_stats(Outcome, type="common")


library(WRS2)
library(rstatix)
# mixed ANOVA
# check assumptions
# outliers
df_responses %>% 
  group_by(Timing, Task) %>%
  identify_outliers(Outcome)
# homogeneity of variances
df_responses %>% levene_test(Outcome ~ Timing)

# normality
df_responses %>% 
  group_by(Timing, Task) %>%
  shapiro_test(Outcome)
# reject H0 for short-hard

# homogeneity of covariances
box_m(df_responses[, "Outcome", drop=FALSE], df_responses$Timing)

# sphericity

# computation
res.aov <- anova_test(
  data=df_responses, dv=Outcome, wid=User_id,
  between=Timing, within=Task
)
get_anova_table(res.aov)

# Post-hoc analysis: main effect of variables
one.way <- df_responses %>% 
  group_by(Task) %>%
  anova_test(dv=Outcome, wid=User_id, between=Timing) %>%
  get_anova_table() %>%
  adjust_pvalue(method="bonferroni")
one.way

# or between group levels: group_by(Task) Outcome~Timing
pwc <- df_responses %>%
  group_by(Timing) %>%
  pairwise_t_test(Outcome~Task, p.adjust.method = "bonferroni")
pwc

# try with non-parametric, the assumptions are not always fulfilled


# If there were no differences bw task levels nor timing, average data from easy and hard and ignore timing
Outcome = df_responses$Outcome
new=dplyr::summarise(group_by(df_responses, User_id, Age, Gender, Education, Rate), Ans=mean(Outcome))
new$Gender = factor(new$Gender)
new$Age = factor(new$Age)
# make 2 groups of AI familiarity
new$Rate[new$Rate>=4] = 'high'
new$Rate[new$Rate<4] = 'low'
new$Rate = factor(new$Rate) # can make 2 groups

# plot and stats
ggplot(new, aes(x=Rate, y=Ans)) + 
  geom_boxplot()

new %>% 
  group_by(Gender) %>%
  get_summary_stats(Ans, type="common")

# independent T-test: 2 levels
t.test(new$Ans~new$Rate)

# one way ANOVA
# check assumptions
new = ungroup(new)
res2.aov <- new %>% anova_test(Ans ~ Age)
res2.aov 


# SURVEY DATA 
# add survey data: only one measurement per short and long
surveyResponses = dplyr::inner_join(user_info, surveyData, by='User_id')
surveyResponses$Timing = factor(surveyResponses$Timing)

df_survey = gather(surveyResponses, key="Question", value="value", 
                   c("Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8"))

ggplot(df_survey, aes(x=Question, y=value, fill=Timing)) + 
  geom_boxplot() + ggtitle("Survey responses") 

# get statistics
df_survey %>% 
  group_by(Timing, Question) %>%
  get_summary_stats(value, type="common")

# analysis: non parametric. 2 conditions: long and short timing
# questions order: Q1-trust, Q2-useful, Q3-reasonable suggestions,
# Q4-tell unreasonable, Q5-enough time, Q6-AI essential, 
# Q7-user contribution, Q8-future use
sub_question = subset(df_survey, df_survey$Question=="Q8")
wilcox.test(value ~ Timing, data=sub_question, exact=FALSE)

# Q9 in on blame
boxplot(Q9 ~ Timing, data=surveyResponses, main="Survey responses blame question")
surveyResponses %>% 
  group_by(Timing) %>%
  get_summary_stats(Q9, type="common")
wilcox.test(Q9 ~ Timing, data=df_survey, exact=FALSE)



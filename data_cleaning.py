import pandas as pd
import os

input_path = '../data/processed/taobao_sampled_1m.csv'
output_path = '../data/processed/taobao_cleaned_1m.csv'

print("开始深度清洗数据...")
df = pd.read_csv(input_path)

init_rows = len(df)
df.dropna(inplace=True)

df.drop_duplicates(inplace=True)
duplicates_removed = init_rows - len(df)
print(f"剔除重复和缺失数据：{duplicates_removed} 条")

df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')
df['timestamp'] = df['timestamp'] + pd.Timedelta(hours=8)

df['date'] = df['timestamp'].dt.date        
df['hour'] = df['timestamp'].dt.hour          

start_date = pd.to_datetime('2017-11-25').date()
end_date = pd.to_datetime('2017-12-03').date()

df = df[(df['date'] >= start_date) & (df['date'] <= end_date)]
final_rows = len(df)
print(f"过滤异常时间数据：{init_rows - duplicates_removed - final_rows} 条")

df.to_csv(output_path, index=False)

print("\n==== 数据清洗结束！ ====")
print(f"原始抽样：{init_rows} 条 -> 清洗后：{final_rows} 条")
print(f"干净的数据已保存至: {output_path}")
print("字段包含: user_id, item_id, category_id, behavior_type, timestamp, date, hour")

print("\n前 5 行预览：")
print(df.head())

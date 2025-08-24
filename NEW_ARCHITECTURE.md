# 🏗️ التصميم الجديد: PostgreSQL → Debezium → Redpanda → Spark → Kafka → Redis

## 🎯 نظرة عامة على التصميم الجديد

تم تحسين معمارية النظام لتصبح أكثر مرونة وقابلية للتوسع. بدلاً من محاولة كتابة البيانات مباشرة من Spark إلى Redis، نقوم الآن بفصل المسؤوليات:

### 📊 المعمارية الجديدة

```
PostgreSQL → Debezium → Redpanda → Spark → enriched_engagement_events → Redis Consumer → Redis Streams
                                    ↓
                              ClickHouse (Analytics)
```

## 🔄 تدفق البيانات

### 1. **PostgreSQL** (المصدر)
- تخزين كتالوج المحتوى وأحداث التفاعل
- التقاط التغييرات عبر Debezium

### 2. **Debezium** (CDC)
- التقاط التغييرات في PostgreSQL
- إرسال البيانات إلى Redpanda topics

### 3. **Redpanda** (Streaming Platform)
- تخزين البيانات الأولية: `postgres.public.content`
- تخزين البيانات الأولية: `postgres.public.engagement_events`
- تخزين البيانات المُثراة: `enriched_engagement_events`

### 4. **Apache Spark** (معالجة البيانات)
- قراءة البيانات من Redpanda
- إثراء البيانات (ربط مع جداول المحتوى)
- حساب `engagement_seconds` و `engagement_percent`
- كتابة البيانات المُثراة إلى:
  - **ClickHouse**: للتحليل والتقارير
  - **Kafka Topic**: `enriched_engagement_events`

### 5. **Redis Consumer** (معالج منفصل)
- قراءة البيانات من `enriched_engagement_events`
- كتابة البيانات إلى Redis Streams
- تحديث التجميعات الزمنية

### 6. **Redis** (التخزين المؤقت)
- Streams للبيانات المُثراة
- Sorted Sets للتجميعات الزمنية
- Hash Maps لملخصات المحتوى

## ✅ مزايا التصميم الجديد

### 1. **فصل المسؤوليات**
- **Spark**: معالجة البيانات والإثراء
- **Redis Consumer**: إدارة Redis والتجميعات
- **ClickHouse**: التحليل والتقارير

### 2. **المرونة والقابلية للتوسع**
- إمكانية إعادة معالجة البيانات من Kafka topic
- إمكانية إضافة consumers آخرين
- إمكانية تغيير Redis Consumer دون التأثير على Spark

### 3. **معالجة الأخطاء**
- إذا فشل Redis Consumer، البيانات تبقى في Kafka
- إمكانية إعادة تشغيل Consumer من آخر نقطة
- لا فقدان للبيانات

### 4. **الأداء**
- Spark يركز على معالجة البيانات
- Redis Consumer يركز على Redis operations
- كل مكون محسن لمهمته

## 🚀 كيفية التشغيل

### 1. **تشغيل النظام الكامل**
```bash
./run_new_pipeline.sh
```

### 2. **تشغيل مكونات منفصلة**
```bash
# تشغيل الخدمات الأساسية
docker compose up -d

# تشغيل Spark Streaming
./spark_stream.sh

# تشغيل Redis Consumer (في terminal منفصل)
docker compose up redis-consumer
```

## 📊 مراقبة النظام

### 1. **مراقبة Redpanda Topics**
```bash
# قائمة المواضيع
docker compose exec redpanda rpk topic list

# مراقبة البيانات المُثراة
docker compose exec redpanda rpk topic consume enriched_engagement_events -n 5
```

### 2. **مراقبة ClickHouse**
```bash
# عدد السجلات المُثراة
docker compose exec clickhouse clickhouse-client -u app --password app -q "
SELECT COUNT(*) as total_enriched FROM app.enriched_engagements;
"
```

### 3. **مراقبة Redis**
```bash
# Streams حسب نوع المحتوى
docker compose exec redis redis-cli xlen "enriched_events:podcast"
docker compose exec redis redis-cli xlen "enriched_events:video"
docker compose exec redis redis-cli xlen "enriched_events:newsletter"

# التجميعات الزمنية
docker compose exec redis redis-cli zrange "top_engaging_content:podcast" 0 -1 WITHSCORES
```

## 🔧 التكوين

### متغيرات البيئة للـ Redis Consumer
```bash
KAFKA_BOOTSTRAP=redpanda:9092
ENRICH_TOPIC=enriched_engagement_events
REDIS_HOST=redis
REDIS_PORT=6379
```

### متغيرات البيئة للـ Spark
```bash
KAFKA_BOOTSTRAP=redpanda:9092
TOPIC_CONTENT=postgres.public.content
TOPIC_EVENTS=postgres.public.engagement_events
ENRICH_TOPIC=enriched_engagement_events
STARTING_OFFSETS=latest
```

## 📈 التجميعات الزمنية

### 1. **Redis Streams**
- `enriched_events:podcast` - أحداث البودكاست
- `enriched_events:video` - أحداث الفيديو
- `enriched_events:newsletter` - أحداث النشرة الإخبارية

### 2. **Redis Sorted Sets**
- `top_engaging_content:podcast` - أفضل البودكاست تفاعلاً
- `top_engaging_content:video` - أفضل الفيديوهات تفاعلاً
- `top_engaging_content:newsletter` - أفضل النشرات تفاعلاً

### 3. **Redis Hash Maps**
- `content_summary:{content_id}` - ملخص تفاعل كل محتوى

## 🛠️ استكشاف الأخطاء

### 1. **إذا لم تصل البيانات إلى Redis**
```bash
# فحص Redis Consumer
docker compose logs redis-consumer

# فحص Kafka topic
docker compose exec redpanda rpk topic describe enriched_engagement_events

# فحص البيانات في Kafka
docker compose exec redpanda rpk topic consume enriched_engagement_events -n 1
```

### 2. **إذا لم تصل البيانات إلى ClickHouse**
```bash
# فحص سجلات Spark
docker compose logs spark-master
docker compose logs spark-worker

# فحص اتصال ClickHouse
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT 1"
```

### 3. **إعادة تشغيل مكون معين**
```bash
# إعادة تشغيل Redis Consumer
docker compose restart redis-consumer

# إعادة تشغيل Spark
docker compose restart spark-master spark-worker
```

## 🔮 التحسينات المستقبلية

### 1. **قريب المدى**
- إضافة Schema Registry
- تحسين استراتيجية التقسيم
- إضافة اختبارات شاملة

### 2. **متوسط المدى**
- إضافة Kafka Connect Sinks أخرى
- دعم أنواع محتوى جديدة
- تحسين استراتيجية التجميع

### 3. **بعيد المدى**
- دعم Multi-Region
- إضافة Machine Learning
- دعم Real-time Analytics

---

**ملاحظة**: هذا التصميم الجديد يحل مشكلة Redis dependency في Spark ويجعل النظام أكثر مرونة وقابلية للتوسع. 
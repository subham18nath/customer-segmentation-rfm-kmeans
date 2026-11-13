import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
import matplotlib.pyplot as plt
import seaborn as sns


def load_and_engineer_rfm(filepath: str, snapshot_str: str = "2026-11-01") -> pd.DataFrame:
    """Load transactional data and compute customer-level RFM & behavioural features."""
    df = pd.read_csv(filepath)
    df["Order_Date"] = pd.to_datetime(df["Order_Date"])
    snapshot_date = pd.Timestamp(snapshot_str)

    rfm = df.groupby(["Customer_ID", "City"]).agg(
        Recency=("Order_Date", lambda x: (snapshot_date - x.max()).days),
        Frequency=("Order_ID", "nunique"),
        Monetary=("Order_Amount_INR", "sum"),
        Avg_Order_Value=("Order_Amount_INR", "mean"),
        Avg_Discount=("Discount_Pct", "mean")
    ).reset_index()

    return rfm


def run_kmeans_segmentation(rfm: pd.DataFrame, n_clusters: int = 4) -> pd.DataFrame:
    """Log-transform, standardize, and cluster customers using K-Means."""
    rfm_log = np.log1p(rfm[["Recency", "Frequency", "Monetary"]])
    scaler = StandardScaler()
    rfm_scaled = scaler.fit_transform(rfm_log)

    kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
    rfm["Cluster_ID"] = kmeans.fit_predict(rfm_scaled)

    sil_score = silhouette_score(rfm_scaled, rfm["Cluster_ID"])
    print(f"K-Means (k={n_clusters}) Silhouette Score: {sil_score:.3f}")

    # Dynamically label clusters based on Monetary & Recency centroids
    summary = rfm.groupby("Cluster_ID").agg(
        Recency=("Recency", "mean"),
        Monetary=("Monetary", "mean")
    )
    ranked = summary.sort_values(by=["Monetary", "Recency"], ascending=[False, True]).index.tolist()
    label_map = {
        ranked[0]: "VIP Champions",
        ranked[1]: "Loyal Spenders",
        ranked[2]: "At-Risk Regulars",
        ranked[3]: "Dormant / Low-Value"
    }
    rfm["Segment"] = rfm["Cluster_ID"].map(label_map)
    return rfm


if __name__ == "__main__":
    rfm_df = load_and_engineer_rfm("data/retail_transactions.csv")
    segmented_df = run_kmeans_segmentation(rfm_df, n_clusters=4)
    segmented_df.to_csv("data/segmented_customers.csv", index=False)

    profile = segmented_df.groupby("Segment").agg(
        Customers=("Customer_ID", "count"),
        Avg_Recency=("Recency", "mean"),
        Avg_Frequency=("Frequency", "mean"),
        Avg_Monetary_INR=("Monetary", "mean"),
        Total_Revenue_INR=("Monetary", "sum")
    ).round(2)
    print("\nSegment Summary:\n", profile)

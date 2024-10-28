import streamlit as st
import matplotlib.pyplot as plt
import numpy as np

# Function to calculate sensitivity and specificity
def calculate_sensitivity_specificity(tp, fn, tn, fp):
    sensitivity = (tp / (tp + fn)) * 100 if (tp + fn) > 0 else 0
    specificity = (tn / (tn + fp)) * 100 if (tn + fp) > 0 else 0
    return sensitivity, specificity

# Function to plot confusion matrix with totals
def plot_confusion_matrix(tp, fn, tn, fp):
    # Create confusion matrix array
    confusion_matrix = np.array([[tp, fn],
                                  [fp, tn]])
    
    # Calculate totals for each row
    total_positives = tp + fn  # Total actual positives
    total_negatives = tn + fp  # Total actual negatives

    # Add totals to the confusion matrix
    total_row = np.array([[total_positives], [total_negatives]])
    extended_matrix = np.hstack((confusion_matrix, total_row))

    fig, ax = plt.subplots()
    
    # Create a heatmap for the confusion matrix
    cax = ax.matshow(extended_matrix, cmap='Blues')

    # Set the colors for TP and TN
    ax.text(0, 0, tp, ha='center', va='center', color='black', bbox=dict(facecolor='lightgreen', alpha=0.5))  # TP
    ax.text(1, 0, fn, ha='center', va='center', color='black', bbox=dict(facecolor='lightcoral', alpha=0.5))  # FN
    ax.text(0, 1, fp, ha='center', va='center', color='black', bbox=dict(facecolor='lightcoral', alpha=0.5))  # FP
    ax.text(1, 1, tn, ha='center', va='center', color='black', bbox=dict(facecolor='lightgreen', alpha=0.5))  # TN
    ax.text(2, 0, total_positives, ha='center', va='center', color='black', fontsize=12, bbox=dict(facecolor='lightgrey', alpha=0.5))  # Total Positives
    ax.text(2, 1, total_negatives, ha='center', va='center', color='black', fontsize=12, bbox=dict(facecolor='lightgrey', alpha=0.5))  # Total Negatives

    # Set ticks and labels
    ax.set_xticks(np.arange(3))
    ax.set_yticks(np.arange(2))
    ax.set_xticklabels(['Predicted Positive', 'Predicted Negative', 'Total'])
    ax.set_yticklabels(['Actual Positive', 'Actual Negative'])

    ax.set_title('Confusion Matrix with Totals')
    plt.xlabel('Predicted Label')
    plt.ylabel('True Label')
    st.pyplot(fig)

# Streamlit app
st.title("Sensitivity and Specificity Calculator")

st.write("""
This app calculates the sensitivity and specificity based on the following inputs:
- True Positives (TP)
- False Negatives (FN)
- True Negatives (TN)
- False Positives (FP)
""")

# Create a two-column layout
col1, col2 = st.columns([2, 1])

# Input fields in the first column
with col1:
    tp = st.number_input("True Positives (TP)", min_value=0, step=1)
    fn = st.number_input("False Negatives (FN)", min_value=0, step=1)
    tn = st.number_input("True Negatives (TN)", min_value=0, step=1)
    fp = st.number_input("False Positives (FP)", min_value=0, step=1)

    # Button to calculate sensitivity and specificity
    if st.button("Calculate"):
        sensitivity, specificity = calculate_sensitivity_specificity(tp, fn, tn, fp)
        
        st.write(f"Sensitivity: {sensitivity:.2f}")
        st.write(f"Specificity: {specificity:.2f}")
        
        # Plot confusion matrix
        plot_confusion_matrix(tp, fn, tn, fp)

# Display an image in the second column
with col2:
    st.image("./images/CM.png", caption="Confusion Matrix", width=500)  # Adjust the width as needed
